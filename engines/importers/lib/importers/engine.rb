# frozen_string_literal: true

module Importers
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    # The admin and API paths are the ones Tools › Import and the CLI used
    # while this was part of the core.
    initializer "importers.routes" do |app|
      app.routes.append do
        namespace :tools do
          resource :import, only: :show do
            scope module: :imports do
              resource :wipe, only: :destroy
            end
          end
          post "import/:source", to: "imports/runs#create", as: :import_run, constraints: {source: /[a-z][a-z0-9_]*/}
        end

        namespace :api, defaults: {format: :json} do
          namespace :tools do
            get    "import",         to: "imports#show"
            delete "import/wipe",    to: "imports/wipes#destroy"
            post   "import/:source", to: "imports/runs#create", as: :import_run, constraints: {source: /[a-z][a-z0-9_]*/}
          end
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :importers, name: "Importers", version: "1.0.0", author: "Martin Business Consultants",
        bundled: true, enabled_by_default: false, requires: ">= 1.0",
        description: "Moving a site in from WordPress, Directus or an Astro repo on GitHub, and wiping the " \
                     "imported content to run one again. Other plugins can add sources."

      Cms::Plugins.importer :importers, "wordpress", Importers::Adapters::Wordpress
      Cms::Plugins.importer :importers, "old_mill", Importers::Adapters::OldMill
      Cms::Plugins.importer :importers, "directus", Importers::Adapters::Directus
      Cms::Plugins.importer :importers, "astro", Importers::Adapters::Astro

      Cms::Plugins.submenu :importers, :tools, label: "Import", path: -> { tools_import_path },
        capability: "tools:use", after: :start
      Cms::Plugins.stylesheet :importers, "importers/importers"

      Cms::Plugins.api :importers, "/api/tools/import", description: "What can be imported; start an import (wordpress, directus, astro)."
      Cms::Plugins.api :importers, "/api/tools/import/wipe", description: "Wipe imported content (confirm with the site key)."
    end
  end
end
