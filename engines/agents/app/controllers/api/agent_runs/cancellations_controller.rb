# frozen_string_literal: true

# POST /api/agent_runs/:id/cancel — asks the run to stop. A queued run stops
# at once; one in flight stops at its worker's next heartbeat.
class Api::AgentRuns::CancellationsController < Api::BaseController
  include Api::AgentRunProtocol

  requires_capability "agents:run", only: :create

  before_action :set_run

  def create
    @run.request_cancel!
    @run.track_event(:canceled, agent: @run.agent_name)
    render "api/agent_runs/run"
  end
end
