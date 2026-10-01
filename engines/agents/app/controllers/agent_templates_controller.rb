# frozen_string_literal: true

# The template library: blueprints you stand up as agents.
#
# Shipped templates (`template_key` present) are re-seeded in place on
# upgrade, so editing one directly would have your changes overwritten. The
# form says so, and "Duplicate" is the way to keep an edit — a copy has no
# key, so no seed will ever touch it.
class AgentTemplatesController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:read",   only: [:index]
  requires_capability "agents:write",  only: [:new, :create, :edit, :update]
  requires_capability "agents:delete", only: [:destroy]

  before_action :set_template, only: [:edit, :update, :destroy]

  def index
    @templates       = AgentTemplate.ordered
    @swarm_templates = SwarmTemplate.ordered
  end

  def new
    @template = AgentTemplate.new(icon: "sparkles", capability_keys: Agents::CapabilityCatalog.default_keys)
  end

  def create
    @template = AgentTemplate.new(template_params)

    if @template.save
      @template.track_event(:created, name: @template.name)
      redirect_to agent_templates_path, notice: "Created #{@template.name}"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      @template.track_event(:updated, name: @template.name)
      redirect_to agent_templates_path, notice: notice_for(@template)
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    name = @template.name
    @template.destroy
    AgentTemplate.track_event(:deleted, name: name)
    redirect_to agent_templates_path,
      notice: "Deleted #{name}. Agents already built from it are unaffected."
  end

  private

  def set_template
    @template = AgentTemplate.find(params[:id])
  end

  def template_params
    permitted = params.require(:agent_template).permit(
      :name, :description, :icon, :category, :instructions, :preferred_model, :cron,
      capability_keys: []
    )
    permitted[:capability_keys] = Array(permitted[:capability_keys]).reject(&:blank?) if permitted.key?(:capability_keys)
    permitted
  end

  # An edit to a shipped template survives until the next seed. Saying so at
  # the moment of saving beats discovering it after an upgrade.
  def notice_for(template)
    return "Saved #{template.name}" unless template.built_in?

    "Saved #{template.name} — but it's a shipped template, so an upgrade will " \
      "overwrite this. Duplicate it to keep your version."
  end
end
