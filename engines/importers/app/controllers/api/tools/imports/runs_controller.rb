# frozen_string_literal: true

# POST /api/tools/import/:source — hands the upload or repo URL to the
# source's adapter (Importers::Adapter), which queues the import: 202.
class Api::Tools::Imports::RunsController < Api::BaseController
  include PluginGated
  plugin :importers

  enforce_authorization
  requires_capability "tools:use", only: :create

  def create
    adapter = Cms::Plugins.enabled_importers[params[:source]] or raise ActiveRecord::RecordNotFound

    @queued = adapter.new(params).queue
    Event.record("import.queued", source: params[:source], **@queued.audit.to_h)
    render :create, status: :accepted
  rescue Importers::Adapter::Invalid => e
    render json: {error: e.code, message: e.api_message}, status: :unprocessable_content
  end
end
