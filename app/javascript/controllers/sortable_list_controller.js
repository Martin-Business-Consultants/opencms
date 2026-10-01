import { Controller } from "@hotwired/stimulus"

// One list of the content editor: blocks, repeater items, string lists and
// record refs. Rows are keyed opaquely, so moving a row only moves it — the
// server reads rows back in the order they're posted (ContentForm).
//
// A new repeater or list row is the list's <template> with its token (the
// list's own __KEYn__, so nested templates keep theirs) replaced by a fresh
// key. A new block comes from the server (content_blocks#new) with its type's
// defaults. Rows reorder by dragging their handle or with the arrow buttons.
export default class extends Controller {
  static targets = [ "list", "item", "template", "picker" ]
  static values = { token: String, url: String, scope: String, depth: Number }

  connect() {
    this.listTarget.addEventListener("dragstart", this.#dragStart)
    this.listTarget.addEventListener("dragover", this.#dragOver)
    this.listTarget.addEventListener("dragend", this.#dragEnd)
  }

  disconnect() {
    this.listTarget.removeEventListener("dragstart", this.#dragStart)
    this.listTarget.removeEventListener("dragover", this.#dragOver)
    this.listTarget.removeEventListener("dragend", this.#dragEnd)
  }

  add() {
    this.#appendTemplate({})
  }

  // A picker in add mode (picker:chosen): append the entry it chose.
  addChosen(event) {
    const { value, label } = event.detail
    if (value) this.#appendTemplate({ "__VALUE__": value, "__LABEL__": label })
  }

  remove(event) {
    this.#row(event)?.remove()
  }

  moveUp(event) {
    const row = this.#row(event)
    const previous = row?.previousElementSibling
    if (previous) previous.before(row)
  }

  moveDown(event) {
    const row = this.#row(event)
    const next = row?.nextElementSibling
    if (next) next.after(row)
  }

  // A copy of a block, right below it, with a new id. Its rich text editors
  // are rebuilt from their current values rather than cloned mid-life.
  duplicate(event) {
    const row = this.#row(event)
    if (!row) return

    const oldScope = row.dataset.rowScope
    const newScope = `${this.scopeValue}[${this.#newKey()}]`
    const clone = row.cloneNode(true)

    clone.querySelectorAll("lexxy-editor").forEach(editor => {
      const input = editor.closest("[data-controller~='rich-text']")?.querySelector("[data-rich-text-target~='input']")
      const fresh = document.createElement("lexxy-editor")
      for (const { name, value } of editor.attributes) fresh.setAttribute(name, value)
      fresh.setAttribute("value", input?.value || "")
      editor.replaceWith(fresh)
    })

    let html = clone.outerHTML
    if (oldScope) {
      html = html.replaceAll(oldScope, newScope).replaceAll(this.#domId(oldScope), this.#domId(newScope))
    }
    row.insertAdjacentHTML("afterend", html)

    const copy = row.nextElementSibling
    copy.dataset.rowScope = newScope
    const id = copy.querySelector("[data-block-id]")
    if (id) {
      id.value = crypto.randomUUID()
      copy.dataset.blockId = id.value
    }
  }

  openPicker(event) {
    this.insertAfter = this.#row(event) || null
    const search = this.pickerTarget.querySelector("input[type=search]")
    if (search) search.value = ""
    this.pickerTarget.querySelectorAll("[data-picker-text]").forEach(item => { item.hidden = false })
    this.pickerTarget.showModal()
    search?.focus()
  }

  closePicker() {
    this.pickerTarget.close()
  }

  filterPicker(event) {
    const query = event.currentTarget.value.trim().toLowerCase()
    this.pickerTarget.querySelectorAll("[data-picker-text]").forEach(item => {
      item.hidden = query !== "" && !item.dataset.pickerText.includes(query)
    })
  }

  async insert(event) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("type", event.currentTarget.dataset.type)
    url.searchParams.set("scope", this.scopeValue)
    url.searchParams.set("depth", this.depthValue)

    const response = await fetch(url, { headers: { Accept: "text/html" }, credentials: "same-origin" })
    if (!response.ok) return

    const html = await response.text()
    if (this.insertAfter && this.insertAfter.isConnected) {
      this.insertAfter.insertAdjacentHTML("afterend", html)
    } else {
      this.listTarget.insertAdjacentHTML("beforeend", html)
    }
    this.element.querySelector(":scope > .content-blocks__empty")?.remove()
    this.closePicker()
  }

  // Drag by the handle only, so text in a row can still be selected.
  grab(event) {
    const row = this.#row(event)
    if (row) row.draggable = true
  }

  #dragStart = (event) => {
    const row = this.#ownRow(event.target)
    if (!row || !row.draggable) return

    event.stopPropagation()
    this.dragged = row
    row.classList.add("content-row--dragging")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", "")
  }

  #dragOver = (event) => {
    if (!this.dragged) return

    event.preventDefault()
    event.stopPropagation()
    const row = this.#ownRow(event.target)
    if (!row || row === this.dragged) return

    const { top, height } = row.getBoundingClientRect()
    if (event.clientY < top + height / 2) {
      row.before(this.dragged)
    } else {
      row.after(this.dragged)
    }
  }

  #dragEnd = () => {
    if (!this.dragged) return

    this.dragged.classList.remove("content-row--dragging")
    this.dragged.draggable = false
    this.dragged = null
  }

  #appendTemplate(replacements) {
    let html = this.templateTarget.innerHTML.replaceAll(this.tokenValue, this.#newKey())
    for (const [placeholder, value] of Object.entries(replacements)) {
      html = html.replaceAll(placeholder, this.#escape(value))
    }
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.listTarget.lastElementChild?.querySelector("input:not([type=hidden]), textarea, select")?.focus()
  }

  // The row of this list an event came from (not a row of a list inside it).
  #row(event) {
    return this.#ownRow(event.target)
  }

  #ownRow(element) {
    let row = element?.closest?.("[data-sortable-list-target~='item']")
    while (row && row.parentElement !== this.listTarget) {
      row = row.parentElement?.closest("[data-sortable-list-target~='item']")
    }
    return row
  }

  #domId(scope) {
    return scope.replaceAll("][", "_").replaceAll("[", "_").replace(/\]$/, "")
  }

  #newKey() {
    return "r" + Math.random().toString(36).slice(2, 7) + Date.now().toString(36)
  }

  #escape(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML.replaceAll('"', "&quot;")
  }
}
