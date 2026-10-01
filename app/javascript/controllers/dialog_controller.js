import { Controller } from "@hotwired/stimulus"
import { orient } from "helpers/orientation_helpers"
import { isTouchDevice } from "helpers/platform_helpers"

export default class extends Controller {
  static targets = [ "dialog", "focusMouse", "focusTouch" ]
  static values = {
    modal: { type: Boolean, default: false },
    sizing: { type: Boolean, default: true },
    autoOpen: { type: Boolean, default: false },
    orient: { type: Boolean, default: true }
  }

  connect() {
    this.dialogTarget.setAttribute("aria-hidden", "true")
    this.dialogTarget.addEventListener("click", this.#closeOnBackdrop)
    if (this.autoOpenValue) this.open()
  }

  disconnect() {
    this.dialogTarget.removeEventListener("click", this.#closeOnBackdrop)
  }

  focusTouchTargetConnected() {
    this.#setupFocus()
  }

  open() {
    const modal = this.modalValue

    if (modal) {
      this.dialogTarget.showModal()
    } else {
      this.dialogTarget.show()
      if (this.orientValue) {
        orient({ target: this.dialogTarget, anchor: this.element })
      }
    }

    this.loadLazyFrames()
    this.dialogTarget.setAttribute("aria-hidden", "false")
    this.dispatch("show")
  }

  toggle() {
    if (this.dialogTarget.open) {
      this.close()
    } else {
      this.open()
    }
  }

  close() {
    this.dialogTarget.close()
    this.dialogTarget.setAttribute("aria-hidden", "true")
    this.dialogTarget.blur()
    orient({ target: this.dialogTarget, reset: true })
    this.dispatch("close")
  }

  closeOnClickOutside({ target }) {
    if (!this.element.contains(target)) this.close()
  }

  preventCloseOnMorphing(event) {
    if (event.detail?.attributeName === "open") {
      event.preventDefault()
      event.stopPropagation()
    }
  }

  loadLazyFrames() {
    Array.from(this.dialogTarget.querySelectorAll("turbo-frame")).forEach(frame => { frame.loading = "eager" })
  }

  captureKey(event) {
    if (event.key !== "Escape") { event.stopPropagation() }
  }

  // A click on the backdrop of a dialog marked closedby="any" (the sheets)
  // closes it, in browsers that don't yet do that themselves (Safari). The
  // backdrop's clicks land on the dialog itself, outside its box.
  #closeOnBackdrop = (event) => {
    const dialog = this.dialogTarget
    if (event.target !== dialog || !dialog.open || dialog.getAttribute("closedby") !== "any") return

    const box = dialog.getBoundingClientRect()
    const inside = event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom
    if (!inside) this.close()
  }

    #setupFocus() {
    const touch = isTouchDevice()
    if (this.hasFocusMouseTarget) this.focusMouseTarget.autofocus = !touch
    if (this.hasFocusTouchTarget) this.focusTouchTarget.autofocus = touch
  }
}
