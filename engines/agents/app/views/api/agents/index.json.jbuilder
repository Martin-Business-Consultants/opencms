# frozen_string_literal: true

json.agents @agents do |agent|
  json.partial! "api/agents/agent", record: agent
end
