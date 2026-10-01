import { Controller } from "@hotwired/stimulus"

// The form builder (forms/edit), after Gravity Forms: a canvas of field
// previews and a side panel that adds fields and edits the picked one.
//
// Each field is a card on the canvas and a settings block in the panel,
// matched by its row key. The card holds the row's first input, so rows post
// in the canvas's order (FormFields reads them back in that order); the
// settings hold the rest, all posted, only the picked one shown. A card's
// preview is drawn here from its settings, as the site would render it.
export default class extends Controller {
  static targets = [ "canvas", "card", "empty", "panel", "settings", "settingsList", "noPick",
                     "cardTemplate", "settingsTemplate", "submitPreview" ]

  connect() {
    this.cardTargets.forEach(card => this.#render(card.dataset.key))
    this.#refresh()
    this.canvasTarget.addEventListener("dragstart", this.#cardDragStart)
    this.canvasTarget.addEventListener("dragover", this.#dragOver)
    this.canvasTarget.addEventListener("drop", this.#drop)
    this.canvasTarget.addEventListener("dragend", this.dragEnd)
    // A required setting left blank sits in a hidden block; open it so the
    // browser can point at it.
    this.element.addEventListener("invalid", this.#invalid, true)
  }

  disconnect() {
    this.canvasTarget.removeEventListener("dragstart", this.#cardDragStart)
    this.canvasTarget.removeEventListener("dragover", this.#dragOver)
    this.canvasTarget.removeEventListener("drop", this.#drop)
    this.canvasTarget.removeEventListener("dragend", this.dragEnd)
    this.element.removeEventListener("invalid", this.#invalid, true)
  }

  // Panel

  showMode(event) {
    this.panelTarget.dataset.mode = event.currentTarget.dataset.mode
  }

  showTab(event) {
    this.panelTarget.dataset.tab = event.currentTarget.dataset.tab
  }

  // A palette button: a new field of its type after the picked one.
  add(event) {
    const { type, label } = event.currentTarget.dataset
    const after = this.#pickedCard()
    this.#insert(type, label, card => after ? after.after(card) : this.canvasTarget.append(card))
  }

  // Cards

  pick(event) {
    if (event.target.closest(".form-card__tools")) return

    this.#pick(event.currentTarget.dataset.key)
  }

  moveUp(event) {
    const card = this.#card(event)
    card.previousElementSibling?.before(card)
  }

  moveDown(event) {
    const card = this.#card(event)
    card.nextElementSibling?.after(card)
  }

  duplicate(event) {
    const card = this.#card(event)
    const key = this.#newKey()
    const settings = this.#settings(card.dataset.key)

    const settingsCopy = this.#copy(settings, card.dataset.key, key)
    settings.after(settingsCopy)
    const cardCopy = this.#copy(card, card.dataset.key, key)
    card.after(cardCopy)

    settingsCopy.dataset.autoname = "false"
    const name = this.#field(settingsCopy, "name")
    name.value = this.#uniqueName(name.value, settingsCopy)
    this.#render(key)
    this.#pick(key)
  }

  remove(event) {
    const card = this.#card(event)
    const key = card.dataset.key
    if (this.picked === key) this.picked = null

    this.#settings(key)?.remove()
    card.remove()
    this.#refresh()
  }

  // Settings

  changed(event) {
    const settings = event.target.closest(".form-settings")
    if (!settings) return

    const role = event.target.dataset.role
    if (role === "name") settings.dataset.autoname = "false"
    if (role === "label" && settings.dataset.autoname === "true") {
      this.#field(settings, "name").value = this.#uniqueName(this.#slug(event.target.value), settings)
    }
    this.#render(settings.dataset.key)
  }

  submitLabel(event) {
    this.submitPreviewTarget.textContent = event.target.value || "Submit"
  }

  // Drag and drop: cards reorder; palette buttons drop in a new field.

  paletteDragStart(event) {
    this.dragging = { type: event.currentTarget.dataset.type, label: event.currentTarget.dataset.label }
    this.placeholder = document.createElement("li")
    this.placeholder.className = "form-card form-card--placeholder"
    event.dataTransfer.effectAllowed = "copy"
    event.dataTransfer.setData("text/plain", "")
  }

  dragEnd = () => {
    this.dragged?.classList.remove("form-card--dragging")
    this.dragged = null
    this.dragging = null
    this.placeholder?.remove()
    this.placeholder = null
  }

  #cardDragStart = (event) => {
    const card = event.target.closest?.(".form-card")
    if (!card) return

    this.dragged = card
    card.classList.add("form-card--dragging")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", "")
  }

  #dragOver = (event) => {
    const moving = this.dragged || this.placeholder
    if (!moving) return

    event.preventDefault()
    const card = event.target.closest?.(".form-card")
    if (!card) {
      if (!moving.isConnected) this.canvasTarget.append(moving)
      return
    }
    if (card === moving) return

    const { top, height } = card.getBoundingClientRect()
    if (event.clientY < top + height / 2) card.before(moving)
    else card.after(moving)
  }

  #drop = (event) => {
    if (!this.dragging) return

    event.preventDefault()
    const { type, label } = this.dragging
    const placeholder = this.placeholder
    this.#insert(type, label, card => placeholder?.isConnected ? placeholder.replaceWith(card) : this.canvasTarget.append(card))
    this.dragEnd()
  }

  #invalid = (event) => {
    // One in a closed sheet (the webhook's) opens it.
    const dialog = event.target.closest("dialog")
    if (dialog && !dialog.open) dialog.showModal()

    const settings = event.target.closest(".form-settings")
    if (!settings) return

    this.#pick(settings.dataset.key)
    this.panelTarget.dataset.tab = event.target.closest(".form-settings__tab").dataset.tab
  }

  // Helpers

  #insert(type, label, place) {
    const key = this.#newKey()
    const card = this.#fromTemplate(this.cardTemplateTarget, key)
    const settings = this.#fromTemplate(this.settingsTemplateTarget, key)
    this.settingsListTarget.append(settings)

    settings.dataset.autoname = "true"
    this.#field(settings, "type").value = type
    this.#field(settings, "label").value = label
    this.#field(settings, "name").value = this.#uniqueName(this.#slug(label), settings)
    if (type === "select" || type === "radio") this.#field(settings, "options").value = "First choice\nSecond choice\nThird choice"

    place(card)
    this.#render(key)
    this.#pick(key)
    card.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  #pick(key) {
    this.picked = key
    this.cardTargets.forEach(card => card.classList.toggle("form-card--picked", card.dataset.key === key))
    this.settingsTargets.forEach(settings => { settings.hidden = settings.dataset.key !== key })
    this.panelTarget.dataset.mode = "settings"
    this.#refresh()
  }

  #refresh() {
    this.emptyTarget.hidden = this.cardTargets.length > 0
    this.noPickTarget.hidden = !!this.picked
  }

  // The card's preview, from its settings: label, the input, description.
  #render(key) {
    const card = this.cardTargets.find(card => card.dataset.key === key)
    const settings = this.#settings(key)
    if (!card || !settings) return

    const value = role => this.#field(settings, role)?.value.trim() || ""
    const type = value("type")
    const required = this.#field(settings, "required")?.checked
    const preview = card.querySelector("[data-role=preview]")
    preview.replaceChildren()

    const label = this.#element("span", "form-card__label", value("label") || "Untitled")
    if (required) label.append(this.#element("span", "form-card__required", " *"))

    if (type === "checkbox") {
      const row = this.#element("span", "form-card__choice")
      row.append(this.#control("input", { type: "checkbox" }), label)
      preview.append(row)
    } else {
      preview.append(label)
      preview.append(this.#input(type, value, settings))
    }

    if (value("help")) preview.append(this.#element("span", "form-card__help", value("help")))
  }

  #input(type, value, settings) {
    const choices = value("options").split("\n").map(line => line.trim()).filter(Boolean)
      .map(line => (line.split(" | ")[1] || line.split(" | ")[0]).trim())

    switch (type) {
      case "textarea":
        return this.#control("textarea", { rows: 3, placeholder: value("placeholder") }, value("default"))
      case "select": {
        const select = this.#control("select")
        select.append(this.#element("option", null, choices[0] || "—"))
        return select
      }
      case "radio": {
        const list = this.#element("span", "form-card__choices")
        choices.forEach(choice => {
          const row = this.#element("span", "form-card__choice")
          row.append(this.#control("input", { type: "radio" }), this.#element("span", null, choice))
          list.append(row)
        })
        return list
      }
      case "file": {
        const several = this.#field(settings, "multiple")?.checked
        return this.#element("span", "form-card__file", several ? "Choose files…" : "Choose a file…")
      }
      default:
        return this.#control("input", { type: "text", placeholder: value("placeholder"), value: value("default") })
    }
  }

  #control(tag, attributes = {}, text = "") {
    const control = document.createElement(tag)
    for (const [name, value] of Object.entries(attributes)) if (value !== "") control.setAttribute(name, value)
    control.className = tag === "input" && attributes.type !== "text" ? "" : "input full-width"
    if (tag === "select") control.classList.add("input--select")
    if (text) control.textContent = text
    control.disabled = true
    control.tabIndex = -1
    return control
  }

  #element(tag, className, text = "") {
    const element = document.createElement(tag)
    if (className) element.className = className
    if (text) element.textContent = text
    return element
  }

  #fromTemplate(template, key) {
    const holder = document.createElement("div")
    holder.innerHTML = template.innerHTML.replaceAll("__KEY__", key)
    return holder.firstElementChild
  }

  // A copy of a card or settings block under a new key, with what was typed
  // into it (outerHTML carries only the values it was rendered with).
  #copy(element, oldKey, newKey) {
    const holder = document.createElement("div")
    holder.innerHTML = element.outerHTML.replaceAll(`[${oldKey}]`, `[${newKey}]`)
    const copy = holder.firstElementChild
    copy.dataset.key = newKey
    copy.classList.remove("form-card--picked")

    const from = element.querySelectorAll("input, select, textarea")
    copy.querySelectorAll("input, select, textarea").forEach((control, index) => {
      if (control.type === "checkbox") control.checked = from[index].checked
      else control.value = from[index].value
    })
    return copy
  }

  // A field name no other field has: "email", then "email_2", "email_3"…
  #uniqueName(base, except = null) {
    base = base || "field"
    const taken = new Set(this.settingsTargets.filter(settings => settings !== except)
      .map(settings => this.#field(settings, "name").value))
    if (!taken.has(base)) return base

    let n = 2
    while (taken.has(`${base}_${n}`)) n++
    return `${base}_${n}`
  }

  #slug(text) {
    return text.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")
  }

  #pickedCard() {
    return this.cardTargets.find(card => card.dataset.key === this.picked)
  }

  #card(event) {
    return event.currentTarget.closest(".form-card")
  }

  #settings(key) {
    return this.settingsTargets.find(settings => settings.dataset.key === key)
  }

  #field(settings, role) {
    return settings.querySelector(`[data-role="${role}"]`)
  }

  #newKey() {
    return "n" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
  }
}
