# frozen_string_literal: true

# Commerce › Quote requests: deleting the requests ticked in the table.
class QuoteRequests::BulkDeletionsController < ApplicationController
  include PluginGated
  plugin :commerce

  requires_capability "quotes:delete", only: :create

  def create
    ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)
    deleted = QuoteRequest.where(id: ids).destroy_all

    if deleted.any?
      QuoteRequest.track_event(:bulk_deleted, count: deleted.size, ids: deleted.map(&:id))
      redirect_to quote_requests_path, notice: "#{deleted.size} quote #{"request".pluralize(deleted.size)} deleted"
    else
      redirect_to quote_requests_path, alert: "Tick the quote requests to delete first."
    end
  end
end
