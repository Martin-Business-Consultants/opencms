# frozen_string_literal: true

# A run as the worker protocol and `cms runs` report it.
json.id record.id
json.agent record.agent_name
json.agent_id record.agent_id
json.swarm record.swarm&.name
json.status record.status
json.trigger record.trigger
json.attempts record.attempts
json.claimed_by record.claimed_by
json.cancel_requested record.cancel_requested?
json.lease_expires_at record.lease_expires_at&.iso8601
json.created_at record.created_at.iso8601
json.started_at record.started_at&.iso8601
json.finished_at record.finished_at&.iso8601
json.duration_seconds record.duration_seconds
json.summary record.summary
json.error record.error
