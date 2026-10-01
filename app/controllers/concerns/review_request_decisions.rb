# frozen_string_literal: true

# What deciding a review request needs: the request, and whether this person
# may publish the record it's about — approval is publishing on the author's
# behalf, so it takes the same capability.
module ReviewRequestDecisions
  extend ActiveSupport::Concern

  included do
    helper_method :can_decide_review?, :reviewable_label
  end

  private

  def set_review_request
    @review_request = ReviewRequest.find(params[:review_request_id])
  end

  def can_decide_review?(request)
    return false if request.reviewable.nil?

    Current.user&.can?("#{capability_prefix(request.reviewable)}:publish") || false
  end

  def capability_prefix(record)
    record.is_a?(Page) ? "pages" : "entries"
  end

  def reviewable_label(record)
    return "(deleted)" if record.nil?

    record.try(:title) || record.try(:slug) || "##{record.id}"
  end

  def forbidden!
    raise Authorization::Forbidden, "review.decide"
  end
end
