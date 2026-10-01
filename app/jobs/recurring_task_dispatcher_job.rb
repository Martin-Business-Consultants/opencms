# frozen_string_literal: true

# Renamed RecurringTask::DispatchJob. Kept one release so a Solid Queue
# schedule still naming it keeps working; remove after that.
class RecurringTaskDispatcherJob < RecurringTask::DispatchJob
end
