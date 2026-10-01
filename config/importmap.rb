# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap
#
# The admin's JavaScript (app/javascript), served as-is: no build step.

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/helpers", under: "helpers"
pin "lexxy"
pin "@rails/activestorage", to: "activestorage.esm.js"
pin "@rails/request.js", to: "@rails--request.js" # @0.0.13
