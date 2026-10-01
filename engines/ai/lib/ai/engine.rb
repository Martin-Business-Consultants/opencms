# frozen_string_literal: true

module Ai
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    initializer "ai.routes" do |app|
      app.routes.append do
        namespace :settings do
          # The OpenCode Zen credential and the default model tier.
          resource :ai, only: [:show, :update], controller: "ais" do
            scope module: :ais do
              resource :test, only: :create
            end
          end
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :ai, name: "AI", version: "1.0.0", author: "Martin Business Consultants",
        bundled: true, enabled_by_default: false, requires: ">= 1.0",
        description: "A language model for the CMS and its plugins: the OpenCode Zen key, the default " \
                     "model tier, and short drafting helpers. Agents run on it in-process when a key is saved.",
        # An install that saved a key, or chose a tier, was using this before
        # it was a plugin.
        adopt_if: -> { Setting.where(key: Ai::Zen::SETTING_KEY).exists? }

      Cms::Plugins.settings :ai, "AI", -> { settings_ai_path },
        description: "The OpenCode Zen key and the default model.", group: "Integrations", after: "GitHub",
        capability: "settings:read"
      Cms::Plugins.provide :ai, :ai, Ai::Gateway
    end
  end
end
