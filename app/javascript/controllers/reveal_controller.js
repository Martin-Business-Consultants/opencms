import { Controller } from "@hotwired/stimulus"

// A secret field (secret_field): masked until the eye is clicked, masked again on a second click.
// The input's type can't be ReActionView state (state in attributes isn't reactive), so this
// flips it and says so on the button.
export default class extends Controller {
  static targets = [ "input", "button" ]

  toggle() {
    const shown = this.inputTarget.type === "password"
    this.inputTarget.type = shown ? "text" : "password"
    this.element.classList.toggle("secret-field--shown", shown)
    this.buttonTarget.setAttribute("aria-pressed", shown)
    this.buttonTarget.title = shown ? "Hide" : "Show"
  }
}
