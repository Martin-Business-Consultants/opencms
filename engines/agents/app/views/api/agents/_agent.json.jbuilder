# frozen_string_literal: true

json.id record.id
json.name record.name
json.description record.description
json.icon record.icon
json.enabled record.enabled
json.instructions record.instructions
json.capabilities record.capability_keys
json.capability_labels record.capability_labels
json.preferred_model record.preferred_model
json.cron record.cron
json.cadence record.cadence_label
json.scope do
  json.label record.scope_label
  json.targets record.scopes_for_brief
end
json.template_key record.template_key
json.next_due_at record.next_due_at&.iso8601
json.last_run_at record.last_run_at&.iso8601
