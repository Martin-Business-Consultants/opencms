# frozen_string_literal: true

# POST /api/agent_runs/claim — the next queued run, leased to this worker.
# 204 when nothing is queued: a polling worker finding an empty queue is the
# normal case, not an error.
class Api::AgentRuns::ClaimsController < Api::BaseController
  include Api::AgentRunProtocol

  requires_capability "agents:run", only: :create

  summarize_run :create
  agent_breadcrumbs(:create) do |payload|
    id = payload.dig("agent_run", "id")
    [crumb("Take the lease", "cms run-start #{id}"),
     crumb("Say what you're doing", "cms run-step #{id} <message>"),
     crumb("Keep the lease alive", "cms run-ping #{id}")]
  end

  def create
    @run = AgentRun.claim!(worker: worker_id, lease: lease_duration)
    return head :no_content unless @run

    @run.track_event(:claimed, worker: worker_id, agent: @run.agent_name)
    render "api/agent_runs/show", status: :ok
  end
end
