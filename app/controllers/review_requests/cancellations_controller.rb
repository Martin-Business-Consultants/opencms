# frozen_string_literal: true

# Withdrawing a review request before anyone decides it.
class ReviewRequests::CancellationsController < ApplicationController
  include ReviewRequestDecisions

  requires_capability "pages:read", only: :create
  before_action :set_review_request

  def create
    if @review_request.cancel!(by: Current.user)
      redirect_to review_requests_path, notice: "Cancelled"
    else
      redirect_to review_requests_path, alert: "Cannot cancel"
    end
  end
end
