# frozen_string_literal: true

# The review request a decision is about, and the capability deciding it
# takes: the reviewable's `:publish` to approve or send back (approving
# publishes), its `:write` to cancel. Resolved from the reviewable, so the
# decision controllers check it inline rather than declaring it.
module Api::ReviewRequestScoped
  extend ActiveSupport::Concern

  included do
    enforce_authorization
    skip_before_action :authorize_action!
    before_action :set_review_request
  end

  private

  def set_review_request
    @review = ReviewRequest.find(params[:review_request_id])
  end

  def require_reviewable_capability!(verb)
    require_capability!("#{capability_prefix(@review.reviewable)}:#{verb}")
  end

  def capability_prefix(record) = record.is_a?(Page) ? "pages" : "entries"

  def acting_user = Current.api_user || Current.user

  def render_already_decided
    render json: {error: "conflict", message: "Already decided"}, status: :conflict
  end
end
