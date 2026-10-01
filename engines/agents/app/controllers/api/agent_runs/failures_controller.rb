# frozen_string_literal: true

# POST /api/agent_runs/:id/fail — gave up, with the reason.
class Api::AgentRuns::FailuresController < Api::BaseController
  include Api::AgentRunProtocol

  requires_capability "agents:run", only: :create

  before_action :set_run

  summarize_run :create

  def create
    failed = @run.fail!(error: params.require(:error), summary: params[:summary])
    return render_conflict(@run) unless failed

    @run.track_event(:failed, agent: @run.agent_name, worker: @run.claimed_by)
    render "api/agent_runs/run"
  end
end
