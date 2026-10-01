# frozen_string_literal: true

# POST /api/review_requests/:id/approve — publishes the reviewable.
class Api::ReviewRequests::ApprovalsController < Api::BaseController
  include Api::ReviewRequestScoped

  def create
    require_reviewable_capability!(:publish)

    if @review.approve!(by: acting_user, comment: params[:comment])
      @review_request = @review
      render "api/review_requests/show"
    else
      render_already_decided
    end
  end
end
