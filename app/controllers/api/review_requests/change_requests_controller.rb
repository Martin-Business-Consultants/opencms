# frozen_string_literal: true

# POST /api/review_requests/:id/request_changes — sends it back to its author.
class Api::ReviewRequests::ChangeRequestsController < Api::BaseController
  include Api::ReviewRequestScoped

  def create
    require_reviewable_capability!(:publish)

    if @review.request_changes!(by: acting_user, comment: params[:comment])
      @review_request = @review
      render "api/review_requests/show"
    else
      render_already_decided
    end
  end
end
