# frozen_string_literal: true

# POST /api/review_requests/:id/cancel — only its author can, which
# ReviewRequest#cancel! enforces: false means "already decided" or "not yours".
class Api::ReviewRequests::CancellationsController < Api::BaseController
  include Api::ReviewRequestScoped

  def create
    require_reviewable_capability!(:write)

    if @review.cancel!(by: acting_user)
      @review_request = @review
      render "api/review_requests/show"
    else
      message = @review.pending? ? "Only the author can cancel this request" : "Already decided"
      render json: {error: "conflict", message: message}, status: :conflict
    end
  end
end
