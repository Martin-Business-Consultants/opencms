import { Controller } from "@hotwired/stimulus"

// A list table's "Bulk actions" select and Apply (layouts/shared/_bulk_actions):
// the chosen option says where the form posts (data-url) and with which status
// (data-status); one that deletes (data-confirm) asks in a dialog first.
export default class extends Controller {
  static targets = [ "choice", "status", "dialog", "controls" ]

  // The select only works with this controller, so it starts hidden; the
  // page's <noscript> buttons stand in for it without JavaScript.
  connect() {
    if (this.hasControlsTarget) this.controlsTarget.hidden = false
  }

  apply() {
    const option = this.choiceTarget.selectedOptions[0]
    if (!option?.value) return

    this.element.action = option.dataset.url
    this.statusTarget.value = option.dataset.status || ""

    if (option.dataset.confirm === "true") {
      this.dialogTarget.showModal()
    } else {
      this.element.requestSubmit()
    }
  }

  cancel() {
    this.dialogTarget.close()
  }
}
