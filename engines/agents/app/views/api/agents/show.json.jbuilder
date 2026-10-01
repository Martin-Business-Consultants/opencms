# frozen_string_literal: true

json.agent do
  json.partial! "api/agents/agent", record: @agent
end
