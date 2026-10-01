import { Controller } from "@hotwired/stimulus"

// WordPress's Screen Options tab on a list screen: which of the table's
// columns show. The choices are built from the table's own headers and kept
// per screen in this browser (localStorage), and they reach rows loaded
// later as the list scrolls. A screen without a table has no tab.
export default class extends Controller {
  static targets = [ "tab", "panel", "choices" ]
  static values = { screen: String }

  connect() {
    this.table = document.querySelector("#main table.data-table")
    this.columns = this.#columns()
    if (this.columns.length < 2) return

    this.tabTarget.hidden = false
    this.#render()
    this.#apply()
    this.observer = new MutationObserver(() => this.#apply())
    this.observer.observe(this.table, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  toggle() {
    const open = this.panelTarget.hidden
    this.panelTarget.hidden = !open
    this.tabTarget.setAttribute("aria-expanded", open)
  }

  change(event) {
    const hidden = new Set(this.#hidden())
    const index = event.target.value
    event.target.checked ? hidden.delete(index) : hidden.add(index)
    this.#store([ ...hidden ])
    this.#apply()
  }

  // Columns a person can hide: every header but the tick-box column and
  // unlabelled ones, by position.
  #columns() {
    if (!this.table) return []
    return Array.from(this.table.tHead?.rows[0]?.cells || []).flatMap((cell, index) => {
      const label = cell.textContent.trim()
      return label && !cell.classList.contains("data-table__check") ? [ { index: String(index), label } ] : []
    }).slice(1) // the first labelled column (the title) always shows, as in WordPress
  }

  #render() {
    const hidden = this.#hidden()
    this.choicesTarget.replaceChildren(...this.columns.map(({ index, label }) => {
      const choice = document.createElement("label")
      choice.className = "screen-options__choice"
      const box = document.createElement("input")
      box.type = "checkbox"
      box.value = index
      box.checked = !hidden.includes(index)
      box.dataset.action = "screen-options#change"
      choice.append(box, document.createTextNode(label))
      return choice
    }))
  }

  #apply() {
    const hidden = new Set(this.#hidden())
    for (const row of this.table.rows) {
      if (row.cells.length === 1) continue // a "load more" row spans them all
      Array.from(row.cells).forEach((cell, index) => { cell.hidden = hidden.has(String(index)) })
    }
  }

  get #key() {
    return `screen-options:${this.screenValue}`
  }

  #hidden() {
    try { return JSON.parse(localStorage.getItem(this.#key) || "[]") } catch { return [] }
  }

  #store(hidden) {
    try { localStorage.setItem(this.#key, JSON.stringify(hidden)) } catch {}
  }
}
