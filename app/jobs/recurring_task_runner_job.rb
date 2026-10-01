# frozen_string_literal: true

# Renamed RecurringTask::RunJob. Kept one release so jobs queued under the old
# name still run; remove once they have drained.
class RecurringTaskRunnerJob < RecurringTask::RunJob
end
