# frozen_string_literal: true

# Stand a template up as an agent. Disabled, always — installing one should
# never start it working.
class AgentTemplates::InstallationsController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:write", only: :create

  def create
    template = AgentTemplate.find(params[:agent_template_id])
    agent = Agent.new(template.to_agent_attributes(name: unique_agent_name(template.name)))

    if agent.save
      agent.track_event(:created, name: agent.name, from_template: template.template_key)
      redirect_to edit_agent_path(agent), notice: "Added #{agent.name}. Set its scope and cadence, then enable it."
    else
      redirect_to agent_templates_path, alert: "Couldn't install #{template.name}: #{agent.errors.full_messages.to_sentence}"
    end
  end

  private

  # Installing the same template twice — one scoped to /blog, one to /docs —
  # is legitimate, and agent names are unique, so disambiguate rather than
  # refusing the second.
  def unique_agent_name(base)
    return base unless Agent.exists?(name: base)

    (2..50).each do |n|
      candidate = "#{base} #{n}"
      return candidate unless Agent.exists?(name: candidate)
    end
    "#{base} #{SecureRandom.hex(3)}"
  end
end
