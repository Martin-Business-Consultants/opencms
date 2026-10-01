# frozen_string_literal: true

# Tools › Import: a tab per importer adapter of the plugins that are on
# (Cms::Plugins.importer), each with its own form, and the wipe that clears
# imported content so an import can run again.
class Tools::ImportsController < ApplicationController
  include PluginGated
  plugin :importers

  requires_capability "tools:use", only: :show

  def show
    @adapters = Cms::Plugins.enabled_importers
    @source = params[:tab].presence_in(@adapters.keys) || @adapters.keys.first
    @wipe_counts = Importers::ContentWipe.counts
  end
end
