# frozen_string_literal: true

# Sending a review request back to its author with changes to make.
class ReviewRequests::ChangeRequestsController < ApplicationController
  include ReviewRequestDecisions

  requires_capability "pages:read", only: :create
  before_action :set_review_request

  def create
    return forbidden! unless can_decide_review?(@review_request)

    if @review_request.request_changes!(by: Current.user, comment: params[:comment])
      redirect_to review_requests_path, notice: "Changes requested"
    else
      redirect_to review_requests_path, alert: "Already decided"
    end
  end
end
