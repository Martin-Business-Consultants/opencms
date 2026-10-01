# frozen_string_literal: true

# Queue a run of one agent now. Deliberately allowed on a disabled agent:
# "disabled" means "don't run on the schedule", and a person pressing the
# button is exactly when you want to try one without turning its cadence on.
class Agents::DispatchesController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:run", only: :create

  def create
    agent = Agent.find(params[:agent_id])
    run = agent.dispatch!(trigger: "manual", triggered_by: Current.user, priority: 1)
    run.track_event(:queued, agent: agent.name, trigger: "manual")

    redirect_to agent_runs_path, notice: queued_notice(agent)
  end

  private

  def queued_notice(agent)
    return "Queued a run for #{agent.name}." if Agents::WorkerHealth.new.seen_recently?

    "Queued a run for #{agent.name} — but no worker has claimed anything recently, " \
      "so it will wait. Check a harness is running."
  end
end
