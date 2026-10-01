import { Controller } from "@hotwired/stimulus"

// The schema editor (app/views/schemas): add, remove and reorder field rows.
// Rows are keyed by an opaque id, so nothing is renumbered — the server reads
// them back in the order they're posted (SchemaFields). A new row is the
// <template> with its __PREFIX__ (the list it joins) and __KEY__ filled in.
export default class extends Controller {
  static targets = [ "template", "row", "name" ]

  add(event) {
    const list = event.currentTarget.closest(".schema-list")
    const fields = list.querySelector(":scope > .schema-list__fields")
    const html = this.templateTarget.innerHTML
      .replaceAll("__PREFIX__", list.dataset.prefix)
      .replaceAll("__KEY__", this.#newKey())

    fields.insertAdjacentHTML("beforeend", html)
    fields.lastElementChild.querySelector("[data-schema-editor-target~=name]")?.focus()
  }

  remove(event) {
    this.#row(event).remove()
  }

  moveUp(event) {
    const row = this.#row(event)
    row.previousElementSibling?.before(row)
  }

  moveDown(event) {
    const row = this.#row(event)
    row.nextElementSibling?.after(row)
  }

  #row(event) {
    return event.currentTarget.closest(".schema-field")
  }

  #newKey() {
    return "n" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
  }
}
