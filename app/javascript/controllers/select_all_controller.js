import { Controller } from "@hotwired/stimulus"

// A tick box that ticks or clears a set of boxes: a list table's header box
// over its rows, or a capability group's box over its capabilities. It shows
// the mixed state (indeterminate) when only some are ticked.
export default class extends Controller {
  static targets = [ "all", "box" ]

  connect() {
    this.sync()
  }

  toggle() {
    this.boxTargets.forEach(box => { box.checked = this.allTarget.checked })
  }

  sync() {
    const ticked = this.boxTargets.filter(box => box.checked).length
    this.allTarget.checked = ticked > 0 && ticked === this.boxTargets.length
    this.allTarget.indeterminate = ticked > 0 && ticked < this.boxTargets.length
  }
}
