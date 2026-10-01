# frozen_string_literal: true

# Renamed Deploys::TriggerJob. Kept one release so jobs queued under the old
# name still run; remove once they have drained.
class TriggerDeployJob < Deploys::TriggerJob
end
