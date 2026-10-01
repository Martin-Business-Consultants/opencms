import { Controller } from "@hotwired/stimulus"

// Copies its content value, or the text at its url value, fetched when clicked. The fetch goes
// inside a ClipboardItem so Safari keeps the click's permission while it loads.
export default class extends Controller {
  static values = { content: String, url: String }
  static classes = [ "success" ]

  async copy(event) {
    event.preventDefault()
    this.reset()

    try {
      if (this.hasUrlValue && this.urlValue) {
        await this.#copyFromUrl()
      } else {
        await navigator.clipboard.writeText(this.contentValue)
      }
      this.element.classList.add(this.successClass)
    } catch {}
  }

  reset() {
    this.element.classList.remove(this.successClass)
    this.#forceReflow()
  }

  async #copyFromUrl() {
    const text = fetch(this.urlValue, { headers: { Accept: "text/plain" }, credentials: "same-origin" })
      .then(response => { if (!response.ok) throw new Error(response.statusText); return response.text() })

    if (window.ClipboardItem && navigator.clipboard.write) {
      await navigator.clipboard.write([ new ClipboardItem({ "text/plain": text.then(t => new Blob([ t ], { type: "text/plain" })) }) ])
    } else {
      await navigator.clipboard.writeText(await text)
    }
  }

  #forceReflow() {
    this.element.offsetWidth
  }
}
