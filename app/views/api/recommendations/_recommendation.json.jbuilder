# frozen_string_literal: true

json.id record.id
json.kind record.kind
json.title record.title
json.body record.body
json.impact record.impact
json.status record.status
json.evidence record.evidence
json.proposed_changes record.proposed_changes
json.actionable record.actionable?
if record.subject_type
  json.subject do
    json.type record.subject_type
    json.id record.subject_id
    json.label record.subject_label
  end
else
  json.subject nil
end
json.agent_run_id record.agent_run_id
json.agent record.filed_by
json.created_at record.created_at.iso8601
json.resolved_at record.resolved_at&.iso8601
json.resolved_by record.resolved_by&.email
