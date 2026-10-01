# frozen_string_literal: true

# POST /api/agent_runs/:id/start — the worker has the lease and is working.
class Api::AgentRuns::StartsController < Api::BaseController
  include Api::AgentRunProtocol

  requires_capability "agents:run", only: :create

  before_action :set_run

  summarize_run :create
  agent_breadcrumbs(:create) do |payload|
    id = payload.dig("agent_run", "id")
    [crumb("Keep the lease alive", "cms run-ping #{id}"),
     crumb("Finish", "cms run-done #{id} <summary>"),
     crumb("Give up, with the reason", "cms run-fail #{id} <error>")]
  end

  def create
    return render_conflict(@run) unless @run.start!(lease: lease_duration)

    render "api/agent_runs/run"
  end
end
