# frozen_string_literal: true

# Stand a swarm template up: the swarm and a seat per member, each seated
# with an agent from the matching agent template. Disabled, like any install.
class SwarmTemplates::InstallationsController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:write", only: :create

  def create
    template = SwarmTemplate.find(params[:swarm_template_id])
    missing = template.missing_template_keys

    if missing.any?
      return redirect_to agent_templates_path,
        alert: "#{template.name} needs agent templates that aren't installed (#{missing.join(", ")}). " \
               "Install the agent templates first."
    end

    swarm = template.instantiate!(name: unique_swarm_name(template.name))
    swarm.track_event(:created, name: swarm.name, from_template: template.template_key)
    redirect_to swarm_path(swarm), notice: "Stood up #{swarm.name}. Set its scope, then enable it."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to agent_templates_path, alert: "Couldn't install #{template.name}: #{e.record.errors.full_messages.to_sentence}"
  end

  private

  def unique_swarm_name(base)
    return base unless Swarm.exists?(name: base)

    (2..50).each do |n|
      candidate = "#{base} #{n}"
      return candidate unless Swarm.exists?(name: candidate)
    end
    "#{base} #{SecureRandom.hex(3)}"
  end
end
