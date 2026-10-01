# frozen_string_literal: true

ReActionView.configure do |config|
  # Compile .html.erb with Herb: HTML-aware ERB, strict locals, and invalid
  # markup shown as an overlay in development and raised in test.
  config.intercept_erb = true

  # Reactive `herb:state` stays off. Runwell v2 found it more trouble than it's
  # worth in 0.6; UI state here is <details>, <dialog> or a Stimulus controller.
  config.slots = false

  config.debug_mode = Rails.env.development?
end
