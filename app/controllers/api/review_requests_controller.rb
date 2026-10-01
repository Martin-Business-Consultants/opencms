# frozen_string_literal: true

# Editorial review over the API. This is how an agent with write-but-not-
# publish capability finishes a job: it drafts, opens a review request, and
# says so — rather than either publishing without permission or leaving the
# work with no signal that it's waiting on someone.
#
#   GET  /api/review_requests
#   POST /api/review_requests
#   POST /api/review_requests/:id/approve          (Api::ReviewRequests::ApprovalsController)
#   POST /api/review_requests/:id/request_changes  (Api::ReviewRequests::ChangeRequestsController)
#   POST /api/review_requests/:id/cancel           (Api::ReviewRequests::CancellationsController)
#
# Capabilities match the admin controller: `pages:read` to look, the
# resource's `:write` to open one, its `:publish` to decide — approving
# publishes, so it takes the same grant publishing does.
class Api::ReviewRequestsController < Api::BaseController
  enforce_authorization
  requires_capability "pages:read", only: [:index]

  # create resolves its capability from the reviewable, so it's checked
  # inline rather than declared here.
  skip_before_action :authorize_action!, only: [:create]

  def index
    @review_requests = ReviewRequest.in_state(params[:state]).limit((params[:limit] || 100).to_i.clamp(1, 500))
  end

  def create
    record = locate_reviewable!
    require_capability!("#{record.is_a?(Page) ? "pages" : "entries"}:write")

    @review_request = record.review_requests.build(
      requested_by: Current.api_user || Current.user,
      comment:      params[:comment].to_s.strip.presence
    )
    @review_request.save!
    @review_request.track_event(:created, reviewable: ReviewRequest.summary_of(record))
    render :show, status: :created
  end

  private

  def locate_reviewable!
    case params[:reviewable_type].to_s
    when "Page"
      params[:slug].present? ? Page.find_by!(path: params[:slug]) : Page.find(params[:reviewable_id])
    when "CollectionEntry"
      if params[:collection_slug].present? && params[:slug].present?
        Collection.find_by!(slug: params[:collection_slug]).entries.find_by!(slug: params[:slug])
      else
        CollectionEntry.find(params[:reviewable_id])
      end
    else
      raise ActionController::ParameterMissing, "reviewable_type must be Page or CollectionEntry"
    end
  end
end
