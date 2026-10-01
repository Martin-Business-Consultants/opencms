# frozen_string_literal: true

# POST /api/pages/bulk_update_status: sets the pages at `paths` to `status`
# (Page.change_status_of), all or nothing.
class Api::Pages::BulkStatusChangesController < Api::BaseController
  include Api::PagePaths

  enforce_authorization
  requires_capability "pages:publish", only: :create

  def create
    @status = params[:status].to_s

    if Page::STATUSES.include?(@status)
      @pages = Page.change_status_of(Page.where(path: bulk_paths).to_a, to: @status)
      @not_found = missing_paths(@pages)
    else
      render json: {error: "invalid", message: "status must be one of #{Page::STATUSES.join(", ")}"},
        status: :unprocessable_content
    end
  end
end
