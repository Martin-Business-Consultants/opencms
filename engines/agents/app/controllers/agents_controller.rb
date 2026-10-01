# frozen_string_literal: true

# The agent roster.
#
# An agent here is a definition, not a process: instructions, the
# capabilities it may use, what part of the site it works, and how often.
# Running one queues a run for a local harness to claim (or, with a key in
# the AI plugin, runs it here), so every button on this page is "queue"
# rather than "start". Queueing is Agents::RunsController; taking a newer
# library version is Agents::UpgradesController.
class AgentsController < ApplicationController
  include PluginGated, NestedRows
  plugin :agents

  requires_capability "agents:read",   only: :index
  requires_capability "agents:write",  only: [:new, :create, :edit, :update]
  requires_capability "agents:delete", only: :destroy

  before_action :set_agent, only: [:edit, :update, :destroy]

  def index
    @agents = Agent.includes(:content_scopes, :swarms).ordered.to_a
    @run_counts = AgentRun.where(agent_id: @agents.map(&:id)).group(:agent_id, :status).count
    @latest = latest_runs_by_agent(@agents)
    @worker = Agents::WorkerHealth.new
    @state = Agents::RosterState.new(agents: @agents, worker: @worker.to_h, latest: @latest, role: Current.user&.role)
    @cards = Agents::Scorecard.new.by_agent
    @activity = Agents::Activity.new
    @spend = Agents::Spend.summary
  end

  def new
    @agent = Agent.new(icon: "sparkles", capability_keys: Agents::CapabilityCatalog.default_keys, enabled: false)
  end

  def create
    @agent = Agent.new(agent_params)
    @agent.granted_by = Current.user&.role

    if @agent.save
      @agent.track_event(:created, name: @agent.name, capabilities: @agent.capability_keys)
      redirect_to agents_path, notice: "Created #{@agent.name}. It's off until you enable it."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @agent.granted_by = Current.user&.role
    if @agent.update(agent_params)
      @agent.track_event(:updated, name: @agent.name)
      redirect_to agents_path, notice: "Saved #{@agent.name}"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    name = @agent.name
    # Runs are nullified rather than cascaded, so deleting an agent keeps the
    # record of what it did — including any findings still in the queue.
    @agent.destroy
    Agent.track_event(:deleted, name: name)
    redirect_to agents_path, notice: "Deleted #{name}"
  end

  private

  def set_agent
    @agent = Agent.find(params[:id])
  end

  def agent_params
    listing_rows(params.require(:agent), :content_scopes_attributes).permit(
      :name, :description, :icon, :instructions, :preferred_model, :cron, :enabled,
      capability_keys: [],
      content_scopes_attributes: [:id, :scope_kind, :value, :_destroy]
    ).tap { |permitted| permitted[:capability_keys]&.compact_blank! }
  end

  # The most recent run per agent, in one query that returns at most one row
  # each. Loading every run and picking the newest in Ruby reads the whole
  # history to render one column — fine on day one, and the roster page's
  # slowest query by a wide margin a year in.
  def latest_runs_by_agent(agents)
    ids = agents.map(&:id)
    return {} if ids.empty?

    AgentRun.where(agent_id: ids)
      .where(id: AgentRun.where(agent_id: ids).group(:agent_id).select("MAX(id)"))
      .index_by(&:agent_id)
  end
end
