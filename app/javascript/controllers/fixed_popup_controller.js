import { Controller } from "@hotwired/stimulus"

// Places a small popup menu in the viewport beside its trigger, so a scrolling list around it
// can't clip it (the work rows on engagement pages). It opens below the trigger, or above
// when there's no room, stays inside the window, and closes if the page scrolls.
export default class extends Controller {
  static targets = [ "trigger", "popup" ]

  connect() {
    this.close = this.close.bind(this)
  }

  disconnect() {
    clearTimeout(this.listening)
    window.removeEventListener("scroll", this.close, true)
  }

  place() {
    const gap = 4
    const margin = 8
    const trigger = this.triggerTarget.getBoundingClientRect()
    const popup = this.popupTarget.getBoundingClientRect()

    // The bottom edge to keep clear of: the window, or the fixed search bar along the bottom.
    const bar = document.querySelector("#footer .bar")?.getBoundingClientRect()
    const floor = Math.min(window.innerHeight, bar && bar.height ? bar.top : window.innerHeight) - margin

    let top = trigger.bottom + gap
    if (top + popup.height > floor) top = Math.max(margin, trigger.top - popup.height - gap)
    const left = Math.min(Math.max(margin, trigger.right - popup.width), window.innerWidth - popup.width - margin)

    this.element.style.setProperty("--popup-top", `${Math.round(top)}px`)
    this.element.style.setProperty("--popup-left", `${Math.round(left)}px`)
    this.element.classList.add("fixed-popup--placed")
    // Listen once opening has settled: showing the menu can nudge the list it sits in.
    clearTimeout(this.listening)
    this.listening = setTimeout(() => window.addEventListener("scroll", this.close, true), 200)
  }

  close(event) {
    if (event && this.popupTarget.contains(event.target)) return

    clearTimeout(this.listening)
    window.removeEventListener("scroll", this.close, true)
    this.element.classList.remove("fixed-popup--placed")
    if (this.popupTarget.open) this.popupTarget.close()
  }
}
