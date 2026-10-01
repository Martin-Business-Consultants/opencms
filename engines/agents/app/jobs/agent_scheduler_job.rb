# frozen_string_literal: true

# Renamed to Agent::ScheduleJob. Kept one release so jobs queued under the old name still
# run; remove after.
class AgentSchedulerJob < Agent::ScheduleJob
end
