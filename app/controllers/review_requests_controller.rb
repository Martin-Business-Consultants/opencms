# frozen_string_literal: true

# Author-facing CRUD for review requests, plus reviewer decisions.
#
# Capabilities:
#   * `pages:write` (or `entries:write`) lets an author submit a request
#     for the corresponding resource.
#   * `pages:publish` (or `entries:publish`) lets a reviewer approve or
#     request changes — same gate that lets them publish directly, since
#     approval is essentially "publish on behalf of the author."
class ReviewRequestsController < ApplicationController
  include ReviewRequestDecisions

  requires_capability "pages:read", only: [:index, :create]

  def index
    @pending  = ReviewRequest.pending.includes(:requested_by, :reviewable).order(created_at: :desc).limit(200)
    @resolved = ReviewRequest.resolved.includes(:requested_by, :reviewer, :reviewable).order(decided_at: :desc).limit(50)
  end

  def create
    record = locate_reviewable!
    return forbidden! unless Current.user&.can?("#{capability_prefix(record)}:write")

    request = record.review_requests.build(
      requested_by: Current.user,
      comment:      params[:comment].to_s.strip.presence
    )
    if request.save
      request.track_event(:created, reviewable: ReviewRequest.summary_of(record))
      redirect_back fallback_location: review_requests_path, notice: "Review requested"
    else
      redirect_back fallback_location: review_requests_path, alert: request.errors.full_messages.join(", ")
    end
  end

  private

  def locate_reviewable!
    case params[:reviewable_type].to_s
    when "Page"            then Page.find(params[:reviewable_id])
    when "CollectionEntry" then CollectionEntry.find(params[:reviewable_id])
    else
      raise ActionController::ParameterMissing, "unknown reviewable_type"
    end
  end
end
