import { Controller } from "@hotwired/stimulus"

// The editor's Publish box: "Save Draft" and "Publish" set the status select
// before the form submits, so the post carries the same status field it always
// has. Buttons without a status (Update, Schedule, Submit for review) submit
// the form as it stands.
export default class extends Controller {
  static targets = [ "status" ]

  submit({ params: { status } }) {
    if (status && this.hasStatusTarget) this.statusTarget.value = status
  }
}
