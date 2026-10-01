# frozen_string_literal: true

json.agent_runs @runs do |run|
  json.partial! "api/agent_runs/summary", record: run
end
