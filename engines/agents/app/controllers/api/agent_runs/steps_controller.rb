# frozen_string_literal: true

# POST /api/agent_runs/:id/report — one progress step onto the run's
# transcript ("read 40 pages, 6 titles over length").
class Api::AgentRuns::StepsController < Api::BaseController
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
    return render_conflict(@run) unless @run.report!(step_params)

    head :accepted
  end

  private

  def step_params
    params.permit(:kind, :message, :detail, :tool).to_h.compact_blank.presence ||
      {"message" => params[:message].to_s}
  end
end
