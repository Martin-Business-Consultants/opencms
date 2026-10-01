# frozen_string_literal: true

# Install (or refresh) the shipped swarm templates. Swarm templates name agent
# templates, so the agent library is seeded first — that's what keeps a
# freshly seeded swarm from being short every seat.
class SwarmTemplates::SeedingsController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:write", only: :create

  def create
    Agents::TemplateLibrary.seed!
    count = Agents::SwarmTemplateLibrary.seed!
    Event.record("swarm_templates.seeded", written: count)
    redirect_to agent_templates_path,
      notice: count.zero? ? "Templates are already up to date." : "Installed #{count} template#{"s" unless count == 1}."
  end
end
