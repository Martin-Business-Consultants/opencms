# frozen_string_literal: true

# The run log — what agents have done, are doing, and are waiting to do.
#
# A run page is the only place the work is legible, because nothing here
# streams: a worker reports progress steps against its lease, so this reads
# the transcript rather than holding a socket open. What is happening right
# now is AgentRuns::LivesController.
class AgentRunsController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:read", only: [:index, :show]

  def index
    runs = AgentRun.includes(:agent, :swarm, :swarm_member, :triggered_by).recent
    @status = params[:status].presence_in(AgentRun::STATUSES)
    @agent_id = params[:agent_id].presence
    runs = runs.where(status: @status) if @status
    runs = runs.where(agent_id: @agent_id) if @agent_id
    @runs = paginate(runs)
    @counts = AgentRun.group(:status).count
    @worker = Agents::WorkerHealth.new
  end

  def show
    @run = AgentRun.find(params[:id])
    # What this run put in front of a human — the point of a run page is to
    # get from "it ran" to "here is what it wants me to look at".
    @recommendations = @run.recommendations.prioritized
    @revisions = revisions_from(@run)
  end

  private

  # Revisions this run proposed: those linked to it (revisions.agent_run_id,
  # set by the in-process gate and by API writes that name the run), plus,
  # for proposals without a link (older rows, a worker that didn't pass
  # agent_run_id), the API proposals made while the run was open. That
  # fallback is approximate on purpose: over-including a human's API write
  # beats a run page that claims it changed nothing.
  def revisions_from(run)
    linked = Revision.where(agent_run_id: run.id)
    return linked.recent.limit(50) unless run.started_at

    window = Revision.where(agent_run_id: nil, source: "api", created_at: run.started_at..(run.finished_at || Time.current))
    linked.or(window).recent.limit(50)
  end
end
