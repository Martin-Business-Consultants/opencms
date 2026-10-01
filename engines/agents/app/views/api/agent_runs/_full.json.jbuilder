# frozen_string_literal: true

# A run with everything a worker needs to do it: the brief, what's happened
# so far, and where to report.
json.partial! "api/agent_runs/summary", record: record
json.brief record.brief
json.transcript record.transcript
json.endpoints do
  json.start api_agent_run_start_url(record)
  json.heartbeat api_agent_run_heartbeat_url(record)
  json.report api_agent_run_report_url(record)
  json.complete api_agent_run_complete_url(record)
  json.fail api_agent_run_fail_url(record)
  json.recommendations api_recommendations_url
end
