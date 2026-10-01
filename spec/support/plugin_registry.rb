# frozen_string_literal: true

# Plugins registered by a spec are removed again afterwards, so the global
# registry (Cms::Plugins) is what the app registered at boot for the next one.
module PluginRegistryHelpers
  REGISTRIES = %i[manifests slots menu_items submenu_items new_items settings_pages permission_groups stylesheets nightly_tasks
    minutely_tasks bootstrap_tasks
    api_endpoints agent_tools agent_capabilities report_definitions importers script_presets block_type_packs
    field_types deploy_providers permission_placements permission_defaults counters manifest_sections
    trash_kinds recurring_recipes providers webhook_event_groups webhook_event_filters].freeze

  def forget_plugin(key)
    key = key.to_sym
    REGISTRIES.each do |name|
      registry = Cms::Plugins.public_send(name)
      if name == :slots
        registry.each_value { it.delete(key) }
      else
        registry.delete(key)
      end
    end
  end

  def switch_plugin(key, on:)
    Cms::Plugins.switch!(key, on: on)
    Current.plugin_states = nil
    Current.plugin_adoptions = nil
  end
end

RSpec.configure do |config|
  config.include PluginRegistryHelpers
  config.before do
    Current.plugin_states = nil
    Current.plugin_adoptions = nil
  end
end
