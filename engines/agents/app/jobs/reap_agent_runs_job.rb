# frozen_string_literal: true

# Renamed to AgentRun::ReapJob. Kept one release so jobs queued under the old name still
# run; remove after.
class ReapAgentRunsJob < AgentRun::ReapJob
end
