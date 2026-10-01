# frozen_string_literal: true

# Take the shipped version of a library template. The roster has already
# shown what changes; this applies it and stamps the version so the agent
# stops claiming to be something it is not.
class Agents::UpgradesController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:write", only: :create

  def create
    agent = Agent.find(params[:agent_id])

    if agent.take_library_upgrade!
      agent.track_event(:upgraded, name: agent.name, template: agent.template_key, version: agent.template_version)
      redirect_to agents_path, notice: "#{agent.name} is on v#{agent.template_version} of #{agent.template_key}."
    else
      redirect_to agents_path, alert: "#{agent.name} is already on the newest version of its template."
    end
  end
end
