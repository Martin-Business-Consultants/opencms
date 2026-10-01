# frozen_string_literal: true

# Starts an import from one adapter (POST /tools/import/:source): the adapter
# stages what it was given and queues the work.
class Tools::Imports::RunsController < ApplicationController
  include PluginGated
  plugin :importers

  requires_capability "tools:use", only: :create

  def create
    adapter = Cms::Plugins.enabled_importers[params[:source]] or raise ActiveRecord::RecordNotFound

    queued = adapter.new(params).queue
    Event.record("import.queued", source: params[:source], **queued.audit.to_h)
    redirect_to tools_import_path(tab: params[:source]), notice: queued.notice
  rescue Importers::Adapter::Invalid => e
    redirect_to tools_import_path(tab: params[:source]), alert: e.message
  end
end
