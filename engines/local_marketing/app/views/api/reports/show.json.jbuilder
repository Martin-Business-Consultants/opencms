# frozen_string_literal: true

json.report do
  json.kind @report.kind
  json.title @report.title
  json.group @report.group
  json.measured_at @report.created_at.iso8601
  json.cost @report.cost.to_f
  json.requested_by @report.requested_by&.email
  json.data @report.data
end
