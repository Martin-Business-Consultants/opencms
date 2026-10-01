import { Controller } from "@hotwired/stimulus"

// A collapsible editor box (content_form_helper#postbox): remembers, per box
// and in this browser only, whether it was left collapsed. The state is put
// back before paint by content_form/_postbox_state; this keeps it current.
const KEY = "postboxes-closed"

export default class extends Controller {
  remember() {
    const closed = new Set(readClosed())
    const key = this.element.dataset.postbox
    if (this.element.open) {
      closed.delete(key)
    } else {
      closed.add(key)
    }
    try { localStorage.setItem(KEY, JSON.stringify([ ...closed ])) } catch (error) {}
  }
}

function readClosed() {
  try { return JSON.parse(localStorage.getItem(KEY) || "[]") } catch (error) { return [] }
}
