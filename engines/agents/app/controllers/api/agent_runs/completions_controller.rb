# frozen_string_literal: true

# POST /api/agent_runs/:id/complete — finished, with a summary and the tokens
# it spent.
class Api::AgentRuns::CompletionsController < Api::BaseController
  include Api::AgentRunProtocol

  requires_capability "agents:run", only: :create

  before_action :set_run

  summarize_run :create
  agent_breadcrumbs(:create) do
    [crumb("Anything you couldn't fix yourself", "cms recommend <kind> <title>"),
     crumb("Next piece of work", "cms work")]
  end

  def create
    completed = @run.complete!(
      summary: params[:summary],
      input_tokens: params[:input_tokens],
      output_tokens: params[:output_tokens]
    )
    return render_conflict(@run) unless completed

    @run.track_event(:completed, agent: @run.agent_name, duration: @run.duration_seconds, worker: @run.claimed_by)
    render "api/agent_runs/run"
  end
end
