# frozen_string_literal: true

# Install (or refresh) the shipped agent templates.
class AgentTemplates::SeedingsController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:write", only: :create

  def create
    count = Agents::TemplateLibrary.seed!
    Event.record("agent_templates.seeded", written: count)
    redirect_to agent_templates_path,
      notice: count.zero? ? "Templates are already up to date." : "Installed #{count} template#{"s" unless count == 1}."
  end
end
