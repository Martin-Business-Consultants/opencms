# frozen_string_literal: true

# Approving a review request publishes the record it's about.
class ReviewRequests::ApprovalsController < ApplicationController
  include ReviewRequestDecisions

  requires_capability "pages:read", only: :create
  before_action :set_review_request

  def create
    return forbidden! unless can_decide_review?(@review_request)

    if @review_request.approve!(by: Current.user, comment: params[:comment])
      redirect_to review_requests_path, notice: "Approved and published"
    else
      redirect_to review_requests_path, alert: "Already decided"
    end
  end
end
