# frozen_string_literal: true

module Hello
  # A CMS plugin: it owns its tables (hello_*), extends the core only through
  # Cms::Plugins and "<event>.cms" notifications, and the core never names it.
  # Remove the gem and the app runs as before.
  class Engine < ::Rails::Engine
    initializer "hello.migrations" do |app|
      config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
    end

    # Routes join the app's own route set (as hello_*), so the core layout's
    # helpers work on the plugin's pages.
    initializer "hello.routes" do |app|
      app.routes.append do
        scope "hello", module: "hello", as: "hello" do
          resources :greetings, only: [:index, :create]
          resource :settings, only: [:show, :update]
        end

        scope "api/hello", module: "hello/api", as: "api_hello", defaults: {format: :json} do
          resources :greetings, only: :index
        end
      end
    end

    # Counts published pages, to show a plugin hearing the core's events.
    initializer "hello.events" do
      ActiveSupport::Notifications.subscribe("page.published.cms") do
        next unless Cms::Plugins.enabled?(:hello)

        Hello::Greeting.record_publication
      end
    end

    config.to_prepare do
      Cms::Plugins.register :hello, name: "Hello", version: "0.1.0", author: "Martin Business Consultants",
        bundled: true, enabled_by_default: false, requires: ">= 1.0",
        description: "The reference plugin: a list of greetings, a dashboard panel, a settings page and an API. " \
                     "Keeps its own table; read it to see how a plugin is built."
      # A top-level menu item with its own submenu, and a link added to the
      # core's Tools submenu (WordPress's add_menu_page / add_submenu_page).
      Cms::Plugins.menu :hello, :hello, label: "Hello", icon: "reaction", group: "Tools", after: :tools,
        path: -> { hello_greetings_path }, capability: "hello:read"
      Cms::Plugins.submenu :hello, :hello, label: "Greetings", path: -> { hello_greetings_path }, capability: "hello:read"
      Cms::Plugins.submenu :hello, :hello, label: "Settings", path: -> { hello_settings_path }, after: "Greetings"
      Cms::Plugins.submenu :hello, :tools, label: "Hello greetings", path: -> { hello_greetings_path },
        capability: "hello:read"
      Cms::Plugins.new_item :hello, label: "Greeting", path: -> { hello_greetings_path(anchor: "new_greeting") },
        capability: "hello:write"
      Cms::Plugins.slot :dashboard, :hello, "hello/slots/dashboard"
      Cms::Plugins.settings :hello, "Hello", -> { hello_settings_path },
        description: "What the greetings say.", capability: "settings:read"
      Cms::Plugins.permissions :hello, "Hello", %w[hello:read hello:write]
      Cms::Plugins.stylesheet :hello, "hello/hello"
      Cms::Plugins.nightly :hello, -> { Hello::Greeting.tidy }
      Cms::Plugins.api :hello, "/api/hello/greetings", description: "The greetings, newest first."
    end
  end
end
