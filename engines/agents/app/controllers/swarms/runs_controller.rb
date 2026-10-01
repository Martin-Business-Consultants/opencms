# frozen_string_literal: true

# Queue every enabled seat of a swarm now, regardless of rota.
class Swarms::RunsController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:run", only: :create

  def create
    swarm = Swarm.find(params[:swarm_id])
    runs = swarm.dispatch_all!(triggered_by: Current.user)
    swarm.track_event(:run, name: swarm.name, queued: runs.size)

    if runs.empty?
      redirect_to swarm_path(swarm), alert: "Nothing to run — every seat in #{swarm.name} is disabled."
    else
      redirect_to swarm_path(swarm), notice: "Queued #{runs.size} run#{"s" unless runs.size == 1}."
    end
  end
end
