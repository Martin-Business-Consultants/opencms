# frozen_string_literal: true

# GET /api_previews/:kind/:id — the JSON tab of a page's, entry's or global's
# editor: the record as the API returns it to a frontend (ApiPreview), with
# the address to fetch it at. Loaded into the tab's frame when it's opened.
class ApiPreviewsController < ApplicationController
  KINDS = {
    "page"   => [Page, "pages:read"],
    "entry"  => [CollectionEntry, "entries:read"],
    "global" => [Global, "globals:read"]
  }.freeze

  skip_authorization

  def show
    model, capability = KINDS.fetch(params[:kind]) { raise ActionController::RoutingError, "unknown kind" }
    return head(:forbidden) unless Current.user&.can?(capability)

    @record = model.find(params[:id])
    @preview = ApiPreview.for(@record)
    render layout: false
  end
end
