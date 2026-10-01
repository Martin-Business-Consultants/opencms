import { Controller } from "@hotwired/stimulus"

// A schema field's `show_if`: shown only while a sibling field (same object)
// has — or hasn't — a value. A hidden field still posts, so what it held is
// kept, as the old editor kept it.
export default class extends Controller {
  connect() {
    this.update()
    this.element.addEventListener("input", this.#changed)
    this.element.addEventListener("change", this.#changed)
  }

  disconnect() {
    this.element.removeEventListener("input", this.#changed)
    this.element.removeEventListener("change", this.#changed)
  }

  update() {
    this.element.querySelectorAll(":scope > [data-show-if]").forEach(field => {
      field.hidden = !this.#visible(JSON.parse(field.dataset.showIf))
    })
  }

  #changed = () => this.update()

  #visible(rule) {
    const current = this.#value(rule.field)
    const same = (a, b) => String(a) === String(b)
    if ("equals" in rule) return same(current, rule.equals)
    if ("not_equals" in rule) return !same(current, rule.not_equals)
    if (Array.isArray(rule.in)) return rule.in.some(v => same(current, v))
    if (Array.isArray(rule.not_in)) return !rule.not_in.some(v => same(current, v))
    return true
  }

  #value(name) {
    const field = this.element.querySelector(`:scope > [data-field-name="${CSS.escape(name)}"]`)
    if (!field) return undefined

    const checkbox = field.querySelector("input[type=checkbox]")
    if (checkbox) return checkbox.checked

    const control = field.querySelector("select, input:not([type=hidden]), textarea") || field.querySelector("input[type=hidden]")
    return control ? control.value : undefined
  }
}
