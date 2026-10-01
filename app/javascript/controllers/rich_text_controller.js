import { Controller } from "@hotwired/stimulus"

// A content form's rich text field. Lexxy edits; the hidden field posts. It
// keeps the stored HTML until the editor actually changes, so text nobody
// touched is saved back exactly as it was.
export default class extends Controller {
  static targets = [ "input", "editor" ]

  change() {
    const html = this.editorTarget.value || ""
    this.inputTarget.value = this.#isEmpty(html) ? "" : html
  }

  #isEmpty(html) {
    return html.replace(/<p>(<br>)?<\/p>/g, "").trim() === ""
  }
}
