# frozen_string_literal: true

json.reports @reports do |report|
  previous = report.previous
  json.kind report.kind
  json.title report.title
  json.group report.group
  json.measured_at report.created_at.iso8601
  json.previous_at previous&.created_at&.iso8601
  json.age_days ((Time.current - report.created_at) / 1.day).floor
  json.metrics report.metrics(against: previous)
  json.warnings report.data["warnings"]
end
json.never_run @never_run
