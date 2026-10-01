# frozen_string_literal: true

# Tools › Redirects: deleting the rules ticked in the table, in one go.
class Tools::Redirects::BulkDeletionsController < ApplicationController
  requires_capability "redirects:delete", only: :create

  def create
    redirects = Redirect.where(id: Array(params[:ids]))

    if redirects.any?
      sources = redirects.map(&:source_path)
      redirects.destroy_all
      Redirect.track_event(:bulk_deleted, count: sources.size, sources: sources)
      redirect_to tools_redirects_path, notice: "#{sources.size} #{"redirect".pluralize(sources.size)} deleted"
    else
      redirect_to tools_redirects_path, alert: "Tick the redirects to delete first."
    end
  end
end
