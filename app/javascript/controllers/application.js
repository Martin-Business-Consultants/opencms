import { Application, defaultSchema } from "@hotwired/stimulus"

// "/" filters the current page, so it gets a key name for data-action filters.
const application = Application.start(document.documentElement, {
  ...defaultSchema,
  keyMappings: { ...defaultSchema.keyMappings, slash: "/" }
})

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }
