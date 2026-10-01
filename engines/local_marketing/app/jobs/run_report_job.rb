# frozen_string_literal: true

# The old name of Report::RunJob, kept for one release so runs queued before
# the rename still execute. Remove once those have drained.
class RunReportJob < Report::RunJob
end
