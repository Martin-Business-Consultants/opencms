import { Controller } from "@hotwired/stimulus"

// A content form's asset field: the chosen asset's id in a hidden field, its
// thumbnail and name beside it. "Choose…" opens the page's shared picker,
// which answers with an asset-picker:picked event naming this field.
export default class extends Controller {
  static targets = [ "input", "preview", "name" ]
  static values = { id: String }

  connect() {
    window.addEventListener("asset-picker:picked", this.#picked)
  }

  disconnect() {
    window.removeEventListener("asset-picker:picked", this.#picked)
  }

  choose() {
    const picker = document.getElementById("asset_picker_dialog")
    if (!picker) return

    picker.dataset.forField = this.idValue
    picker.showModal()
    // A lazy frame in a modal dialog isn't loaded by Turbo's visibility check.
    picker.querySelectorAll("turbo-frame[loading=lazy]").forEach(frame => { frame.loading = "eager" })
  }

  clear() {
    this.inputTarget.value = ""
    this.previewTarget.replaceChildren()
    this.nameTarget.textContent = "No file chosen"
  }

  #picked = (event) => {
    if (event.detail.field !== this.idValue) return

    this.inputTarget.value = event.detail.id
    this.nameTarget.textContent = event.detail.name
    this.previewTarget.innerHTML = event.detail.thumb || ""
  }
}
