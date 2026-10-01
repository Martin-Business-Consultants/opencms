# frozen_string_literal: true

# The Forms plugin's Stimulus controllers, loaded with the admin's own
# (controllers/index.js loads every pin under "controllers"): forms--builder.
pin_all_from Forms::Engine.root.join("app/javascript/controllers/forms"), under: "controllers/forms", to: "controllers/forms"
