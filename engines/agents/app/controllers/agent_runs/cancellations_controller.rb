# frozen_string_literal: true

# Ask a run to stop. A queued run stops at once; one in flight stops at its
# worker's next check-in.
class AgentRuns::CancellationsController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:run", only: :create

  def create
    run = AgentRun.find(params[:agent_run_id])
    run.request_cancel!
    run.track_event(:canceled, agent: run.agent_name)

    notice = run.canceled? ? "Canceled." : "Asked #{run.claimed_by || "the worker"} to stop — it stops at its next check-in."
    redirect_to agent_run_path(run), notice: notice
  end
end
