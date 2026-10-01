// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "reactionview"
import * as ActiveStorage from "@rails/activestorage"
import { highlightCode } from "lexxy"

// File fields with direct_upload: true send their files straight to storage (the file
// manager's uploads).
ActiveStorage.start()

// Code blocks in rich text, coloured on the page as they are in the editor. Lexxy's highlighter
// skips blocks it has done, so running it after every Turbo render is safe.
for (const event of [ "turbo:load", "turbo:render", "turbo:frame-load" ]) {
  document.addEventListener(event, () => highlightCode())
}

// A confirm dialog whose button just submitted (delete, bulk delete) closes before the
// page comes back. The response usually redirects to the same page, which Turbo morphs,
// and a modal <dialog> that only loses its open attribute in the morph stays in the top
// layer, leaving the whole page inert.
document.addEventListener("turbo:submit-end", (event) => {
  const trigger = event.detail.formSubmission?.submitter || event.target
  trigger.closest("dialog[open]")?.close()
})
