# frozen_string_literal: true

# What a protocol step (start, complete, fail, cancel) answers: the run as it
# stands now.
json.agent_run do
  json.partial! "api/agent_runs/summary", record: @run
end
