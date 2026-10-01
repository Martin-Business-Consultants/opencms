import { Controller } from "@hotwired/stimulus"

// A native <input type="date">, a little easier to use: a click anywhere on it opens the
// browser's picker (not only the small calendar icon), and from the keyboard t picks today,
// + and - move a day, and Backspace or Delete clears it. Nothing else: the browser's own
// control does the rest, and the value is always YYYY-MM-DD.
export default class extends Controller {
  open() {
    if (this.element.disabled || this.element.readOnly) return
    try { this.element.showPicker() } catch {}
  }

  shortcut(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return

    switch (event.key) {
      case "t": case "T": this.#set(new Date()); break
      case "+": case "=": this.#shift(1); break
      case "-": case "_": this.#shift(-1); break
      case "Backspace": case "Delete":
        if (this.element.required) return
        this.element.value = ""
        this.#changed()
        break
      default: return
    }
    event.preventDefault()
  }

  // From the field's own YYYY-MM-DD as a local date, so daylight saving can never slip a day.
  #shift(days) {
    const [ year, month, day ] = this.element.value.split("-").map(Number)
    const date = year ? new Date(year, month - 1, day) : new Date()
    date.setDate(date.getDate() + days)
    this.#set(date)
  }

  #set(date) {
    const pad = (n) => String(n).padStart(2, "0")
    this.element.value = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
    this.#changed()
  }

  #changed() {
    this.element.dispatchEvent(new Event("input", { bubbles: true }))
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
