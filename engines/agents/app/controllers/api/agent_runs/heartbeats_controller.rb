# frozen_string_literal: true

# POST /api/agent_runs/:id/heartbeat — extends the lease, and answers whether
# to carry on: `continue: false` means the run was canceled or handed to
# another worker, and the caller stops.
class Api::AgentRuns::HeartbeatsController < Api::BaseController
  include Api::AgentRunProtocol

  requires_capability "agents:run", only: :create

  before_action :set_run

  def create
    @extended = @run.heartbeat!(lease: lease_duration)
    @reason = reason(@extended)
  end

  private

  def reason(extended)
    return "canceled" if @run.cancel_requested?
    return nil if extended

    "This run is #{@run.status} and is no longer yours — stop work."
  end
end
