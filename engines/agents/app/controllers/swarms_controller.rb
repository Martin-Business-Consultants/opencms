# frozen_string_literal: true

# Swarms — a standing team of agents on a rota.
#
# The reason a swarm isn't just a bigger agent is cadence. SEO work splits
# into jobs with genuinely different rhythms, and one agent means running the
# cheap work as rarely as the expensive work, or the reverse. Queueing every
# seat now is Swarms::RunsController.
class SwarmsController < ApplicationController
  include PluginGated, NestedRows
  plugin :agents

  requires_capability "agents:read",   only: [:index, :show]
  requires_capability "agents:write",  only: [:new, :create, :edit, :update]
  requires_capability "agents:delete", only: :destroy

  before_action :set_swarm, only: [:show, :edit, :update, :destroy]

  def index
    @swarms = Swarm.includes(:content_scopes, swarm_members: :agent).ordered.to_a
    @templates = SwarmTemplate.ordered
  end

  def show
    @members = @swarm.swarm_members.includes(:agent).ordered
    @runs = @swarm.agent_runs.includes(:swarm_member).recent.limit(100).to_a
    # The set, judged as a set: whether the cycle was worth running, which
    # only the whole cycle's output can answer.
    @cycle = Agents::CycleSynthesis.new(@swarm).to_h
    @activity = Agents::Activity.new(@swarm.agent_runs)
  end

  def new
    @swarm = Swarm.new(icon: "users", enabled: false)
  end

  def create
    @swarm = Swarm.new(swarm_params)

    if @swarm.save
      @swarm.track_event(:created, name: @swarm.name, members: @swarm.swarm_members.size)
      redirect_to swarm_path(@swarm), notice: "Created #{@swarm.name}. It's off until you enable it."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @swarm.update(swarm_params)
      @swarm.track_event(:updated, name: @swarm.name)
      redirect_to swarm_path(@swarm), notice: "Saved #{@swarm.name}"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    name = @swarm.name
    # Seats go; the agents they seated stay. An agent is a thing in its own
    # right, and deleting a team shouldn't delete its members.
    @swarm.destroy
    Swarm.track_event(:deleted, name: name)
    redirect_to swarms_path, notice: "Deleted #{name}. Its agents are still in the roster."
  end

  private

  def set_swarm
    @swarm = Swarm.find(params[:id])
  end

  def swarm_params
    listing_rows(params.require(:swarm), :content_scopes_attributes, :swarm_members_attributes).permit(
      :name, :description, :icon, :enabled,
      content_scopes_attributes: [:id, :scope_kind, :value, :_destroy],
      swarm_members_attributes: [:id, :agent_id, :role, :model, :frequency, :day, :hour,
        :position, :enabled, :_destroy]
    )
  end
end
