# frozen_string_literal: true

require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Middleware is referenced while the app boots, before the autoloader runs,
# so it's required here and kept out of autoload_lib below.
require_relative "../lib/middleware/svg_sandbox"

module ReactStarterKit
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # The site this install serves (Site.key): what the API sends as
    # `tenant`. Defaults to the first label of APP_HOST.
    config.x.site_key = ENV["SITE_KEY"].presence

    # Use libvips (provided by the nix flake) for image variant processing.
    config.active_storage.variant_processor = :vips

    # Serve SVG uploads inline as image/svg+xml so the consumer site can use
    # them in <img> tags (Rails' default forces them to download as
    # application/octet-stream). An SVG opened directly could run script on
    # this origin, which hosts the admin, so SvgSandbox
    # (lib/middleware/svg_sandbox.rb) serves all SVG responses under a
    # `sandbox` Content-Security-Policy that disables it.
    config.active_storage.content_types_to_serve_as_binary -= ["image/svg+xml"]
    config.active_storage.content_types_allowed_inline += ["image/svg+xml"]
    config.middleware.insert_before 0, SvgSandbox

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets middleware tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
