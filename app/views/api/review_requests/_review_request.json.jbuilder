# frozen_string_literal: true

json.id record.id
json.state record.state
json.comment record.comment
json.decision_comment record.decision_comment
json.requested_by record.requested_by&.email
json.reviewer record.reviewer&.email
json.created_at record.created_at.iso8601
json.decided_at record.decided_at&.iso8601
json.reviewable ReviewRequest.summary_of(record.reviewable)
