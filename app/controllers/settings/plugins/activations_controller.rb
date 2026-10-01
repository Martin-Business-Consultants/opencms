# frozen_string_literal: true

# Switching a plugin on (create) and off (destroy). Off keeps its tables and
# data; on again picks them back up.
class Settings::Plugins::ActivationsController < Settings::BaseController
  requires_capability "settings:write", only: [:create, :destroy]

  before_action :set_plugin

  def create
    if !@plugin.compatible?
      redirect_to settings_plugins_path, alert: "#{@plugin.name} needs CMS #{@plugin.requires}; this is #{Cms::VERSION}."
    else
      @granted = Cms::Plugins.switch!(@plugin.key, on: true)
      Event.record("plugin.enabled", plugin: @plugin.key.to_s, version: @plugin.version)
      Event.record("plugin.permissions_granted", plugin: @plugin.key.to_s, roles: @granted) if @granted.any?
      redirect_to settings_plugins_path, notice: activation_notice
    end
  end

  def destroy
    Cms::Plugins.switch!(@plugin.key, on: false)
    Event.record("plugin.disabled", plugin: @plugin.key.to_s, version: @plugin.version)
    redirect_to settings_plugins_path, notice: "#{@plugin.name} is off. Its data stays until you switch it on again."
  end

  private

  def set_plugin
    @plugin = Cms::Plugins.manifests[params[:plugin_key].to_s.to_sym] or raise ActiveRecord::RecordNotFound
  end

  def activation_notice
    missing = Cms::Plugins.missing_dependencies(@plugin.key).filter_map { Cms::Plugins.manifests[it]&.name || it.to_s }
    notice = if missing.any?
      "#{@plugin.name} is switched on, and starts working once #{missing.to_sentence} #{missing.one? ? "is" : "are"} on too."
    else
      "#{@plugin.name} is on."
    end
    notice += " #{@granted.keys.to_sentence} got its standard permissions." if @granted.any?
    notice
  end
end
