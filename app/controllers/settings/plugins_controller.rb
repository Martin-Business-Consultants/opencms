# frozen_string_literal: true

# Settings › Plugins: what this install adds to the core (engines/ and
# plugins/, Cms::Plugins), whether each is on, and why one can't be.
class Settings::PluginsController < Settings::BaseController
  requires_capability "settings:read", only: [:index, :show]

  before_action :set_plugin, only: :show

  def index
    @plugins = Cms::Plugins.manifests.values.sort_by(&:name)
  end

  def show
  end

  private

  def set_plugin
    @plugin = Cms::Plugins.manifests[params[:key].to_s.to_sym] or raise ActiveRecord::RecordNotFound
  end
end
