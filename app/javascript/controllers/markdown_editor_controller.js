import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

// A Markdown field's Write / Preview tabs. Preview asks the server to render
// the textarea's text (MarkdownPreviewsController); the textarea stays in
// the form either way, so what posts is always the Markdown.
export default class extends Controller {
  static targets = [ "input", "output", "writeTab", "previewTab" ]
  static values = { url: String }

  write() {
    this.#show(false)
    this.inputTarget.focus()
  }

  async preview() {
    this.outputTarget.innerHTML = "<p class=\"txt-subtle\">Rendering…</p>"
    this.#show(true)
    const response = await post(this.urlValue, { body: { text: this.inputTarget.value }, responseKind: "html" })
    this.outputTarget.innerHTML = response.ok ? await response.text : "<p class=\"txt-negative\">The preview couldn’t be drawn.</p>"
  }

  #show(previewing) {
    this.inputTarget.hidden = previewing
    this.outputTarget.hidden = !previewing
    this.writeTabTarget.setAttribute("aria-selected", String(!previewing))
    this.previewTabTarget.setAttribute("aria-selected", String(previewing))
  }
}
