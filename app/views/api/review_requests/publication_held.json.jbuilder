# frozen_string_literal: true

# A write that would have published a draft (or created a record published)
# from someone without the publish capability (GatedWrites). The rest of it
# saved; `ignored_fields` names what didn't, and the review request is what
# publishes it once approved. The same status as a held-back live edit.
json.status "pending_review"
json.message "Saved as a draft — publishing it is waiting for review."
json.review_request do
  json.id review_request.id
  json.state review_request.state
  json.created_at review_request.created_at.iso8601
end
json.record ReviewRequest.summary_of(record)
json.review_url review_requests_url
json.ignored_fields ignored
