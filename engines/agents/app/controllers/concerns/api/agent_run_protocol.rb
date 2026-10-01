# frozen_string_literal: true

# What every step of the worker protocol shares (Api::AgentRunsController and
# Api::AgentRuns::*): the run it acts on, the lease it asks for, and the JSON
# a harness reads back.
#
# A local harness (installed by `agent/install.sh`) drives the whole
# lifecycle: claim a queued run, get its frozen brief, report progress
# against a lease, finalize. The CMS never calls a model here — it hands out
# work and records what came back.
#
# Everything that advances a run is gated on `agents:run` rather than
# `agents:write`. That separation is the point: a worker executes the
# roster, and cannot rewrite the instructions it is executing, or approve the
# changes it proposes.
module Api::AgentRunProtocol
  extend ActiveSupport::Concern

  included do
    include PluginGated
    plugin :agents
    enforce_authorization
  end

  class_methods do
    # "Run 12 · Sweep · running." — for the agent envelope.
    def summarize_run(*actions)
      agent_summary(*actions) do |payload|
        run = payload["agent_run"] or next nil
        agent = run["agent"]
        name = agent.is_a?(Hash) ? agent["name"] : agent
        ["Run #{run["id"]}", name, run["status"]].compact.join(" · ") + "."
      end
    end
  end

  private

  def set_run
    @run = AgentRun.find(params[:id])
  end

  def worker_id
    params[:worker].presence || Current.api_token.try(:name).presence || "unknown-worker"
  end

  # A worker may ask for a longer or shorter lease; within bounds, so a
  # typo can't pin a run for a day or expire it before the first step.
  def lease_duration
    seconds = params[:lease_seconds].presence&.to_i
    return AgentRun::DEFAULT_LEASE if seconds.nil? || seconds <= 0

    seconds.clamp(60, 3_600).seconds
  end

  # 409 when the run isn't in a state this worker may advance — finished,
  # reaped, or someone else's after a requeue.
  def render_conflict(run)
    render json: {
      error: "conflict",
      message: "Run ##{run.id} is #{run.status} — it is not yours to advance.",
      status: run.status
    }, status: :conflict
  end
end
