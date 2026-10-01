# frozen_string_literal: true

# Hand a do-next item to the agent that does that kind of work: install the
# template if it isn't, queue one run. The agent stays as it was — a one-off
# run is not the same as turning it on. Agents come from the Agents plugin
# (Cms::Plugins.provided(:agents)).
class Marketing::HandOffsController < ApplicationController
  include PluginGated
  plugin :local_marketing

  requires_capability "reports:run", only: :create

  def create
    key = params[:template].to_s

    case (run = Marketing.hand_off(key, by: Current.user, finding_id: params[:finding_id]))
    when :no_agents then redirect_to marketing_path, alert: "Switch on the Agents plugin to hand work to an agent."
    when :unknown_template then redirect_to marketing_path, alert: "No agent template called #{key}."
    else redirect_to marketing_path, notice: "Handed to #{run.agent_name} — see Runs."
    end
  end
end
