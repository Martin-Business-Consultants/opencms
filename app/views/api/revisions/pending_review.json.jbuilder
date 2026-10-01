# frozen_string_literal: true

# A write the review gate held back (GatedWrites). `ignored` tells a client
# its `status` change went nowhere rather than letting it believe it
# published something.
json.status "pending_review"
json.message "Saved as a revision for review — the live content is unchanged."
json.revision do
  json.id revision.id
  json.state revision.state
  json.fields revision.changed_keys
  json.created_at revision.created_at.iso8601
end
json.review_url revision_url(revision)
json.ignored_fields ignored if ignored.any?
