# frozen_string_literal: true

# Renamed to AgentRun::ExecutionJob. Kept one release so jobs queued under the old name still
# run; remove after.
class AgentRunJob < AgentRun::ExecutionJob
end
