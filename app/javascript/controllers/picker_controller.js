import { Controller } from "@hotwired/stimulus"

// A content form's searchable picker (a reference or link field). The field
// it posts is a plain text input holding the stored value, so without
// JavaScript it still works (type the slug). With it, that input hides and a
// search box asks the server for matches as you type (content_pickers), shown
// in a turbo-frame; arrow keys move through them, Enter picks, Escape closes.
export default class extends Controller {
  static targets = [ "value", "query", "frame", "results" ]
  // mode "add": a list's "Add an entry…" picker, which posts nothing itself;
  // picking announces the choice (picker:chosen) for the list to append.
  static values = { url: String, mode: String }

  #timer = null

  connect() {
    this.valueTarget.type = "hidden"
    this.queryTarget.hidden = false
  }

  search() {
    clearTimeout(this.#timer)
    this.#timer = setTimeout(() => this.#load(), 180)
  }

  open() {
    if (this.resultsTarget.hidden) this.#load()
  }

  navigate(event) {
    const choices = this.#choices()
    const index = choices.indexOf(document.activeElement)
    if (event.key === "ArrowDown") {
      event.preventDefault()
      if (this.resultsTarget.hidden) return this.#load()
      choices[Math.min(index + 1, choices.length - 1)]?.focus()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      if (index <= 0) this.queryTarget.focus()
      else choices[index - 1]?.focus()
    } else if (event.key === "Escape") {
      if (!this.resultsTarget.hidden) {
        event.preventDefault()
        event.stopPropagation()
        this.#close()
        this.queryTarget.focus()
      }
    } else if (event.key === "Enter" && document.activeElement === this.queryTarget) {
      event.preventDefault()
      choices[0]?.click()
    }
  }

  choose(event) {
    const choice = event.currentTarget
    if (this.modeValue === "add") {
      this.dispatch("chosen", { detail: { value: choice.dataset.value, label: choice.dataset.label } })
      this.queryTarget.value = ""
      this.#close()
      this.queryTarget.focus()
      return
    }
    this.valueTarget.value = choice.dataset.value
    this.queryTarget.value = choice.dataset.label
    this.#close()
    this.queryTarget.focus()
    this.valueTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  clear() {
    if (this.queryTarget.value.trim() === "") this.valueTarget.value = ""
  }

  dismiss(event) {
    if (!this.element.contains(event.target)) this.#close()
  }

  #load() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", this.queryTarget.value)
    url.searchParams.set("frame", this.frameTarget.id)
    this.frameTarget.src = url.toString()
    this.resultsTarget.hidden = false
  }

  #close() {
    this.resultsTarget.hidden = true
  }

  #choices() {
    return Array.from(this.frameTarget.querySelectorAll(".picker__choice"))
  }
}
