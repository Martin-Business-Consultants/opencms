# frozen_string_literal: true

json.agent_run do
  json.partial! "api/agent_runs/full", record: @run
end
