# frozen_string_literal: true

module ConsentScripts
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    # Same paths and route names as when this was part of the core, so the
    # sites loading /consent.js and the CLI reading /api/scripts don't change.
    initializer "consent_scripts.routes" do |app|
      app.routes.append do
        # Third-party tags and the consent banner that gates them. `/consent.js`
        # is the public embed the site loads; it carries the config and the
        # active scripts and is the only public route here.
        resources :scripts, except: :show
        get "consent.js",   to: "consent#script", as: :consent_script, defaults: {format: :js}
        get "consent.json", to: "consent#show",   as: :consent_json,   defaults: {format: :json}

        namespace :settings do
          # The consent banner: copy, categories, opt-in vs opt-out. `reconsent`
          # bumps the version so every visitor is asked again.
          resource :consent, only: [:show, :update], controller: "consents" do
            scope module: :consents do
              resource :reconsent, only: :create
            end
          end
        end

        namespace :api, defaults: {format: :json} do
          # The consent config and active scripts, for a site that renders its own
          # banner at build time instead of loading /consent.js.
          get "consent", to: "consents#show"
          resources :scripts, only: [:index]
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :consent_scripts, name: "Consent & Scripts", version: "1.0.0",
        author: "Martin Business Consultants", bundled: true, enabled_by_default: true, requires: ">= 1.0",
        description: "The third-party tags the site loads — analytics, pixels, chat — and the cookie banner " \
                     "that asks visitors before any of them run.",
        adopt_if: -> { Script.exists? || Setting.exists?(key: Consent::Config::KEY) }

      Cms::Plugins.submenu :consent_scripts, :tools, label: "Scripts", path: -> { scripts_path },
        capability: "scripts:read", after: "Redirects"
      Cms::Plugins.settings :consent_scripts, "Consent", -> { settings_consent_path },
        description: "The cookie banner and its categories.", capability: "consent:read",
        group: "Workspace", after: "Commerce"

      # Reading is harmless; a script is JavaScript in every visitor's browser,
      # so writing sits with the roles that already change how the site runs.
      Cms::Plugins.permissions :consent_scripts, "Scripts", %w[scripts:read scripts:write scripts:delete],
        after: "Redirects",
        defaults: {editor: %w[scripts:read consent:read], site: %w[scripts:read consent:read]}
      Cms::Plugins.permissions :consent_scripts, "Consent", %w[consent:read consent:write], after: "Scripts"

      Cms::Plugins.provide :consent_scripts, :consent_config, -> { Consent::Config.load }
      Cms::Plugins.provide :consent_scripts, :scripts, -> { Script.ordered.to_a }

      Cms::Plugins.api :consent_scripts, "/api/scripts", description: "Every script the site runs, with its consent category."
      Cms::Plugins.api :consent_scripts, "/api/consent", description: "The consent config and active scripts, for a site that renders its own banner."
    end
  end
end
