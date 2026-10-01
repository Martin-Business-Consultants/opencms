import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Reloads the page every `interval` seconds while it's connected, morphing it
// in place (the layout refreshes with morph). The server leaves the
// controller off once there's nothing left to wait for, which stops it.
export default class extends Controller {
  static values = { interval: { type: Number, default: 3 } }

  connect() {
    this.timer = setInterval(() => Turbo.visit(window.location.href, { action: "replace" }), this.intervalValue * 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
