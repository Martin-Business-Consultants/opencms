# frozen_string_literal: true

# What is happening right now, and what just happened.
#
# A separate screen from the run log because it answers a different
# question. The log is "what did this agent do last Tuesday", read by
# someone with a reason to look; this is "is anything working", read at a
# glance, and it refreshes itself.
class AgentRuns::LivesController < ApplicationController
  include PluginGated
  plugin :agents

  requires_capability "agents:read", only: :show

  def show
    runs = AgentRun.includes(:agent, :swarm, :swarm_member, :triggered_by)
    @active = runs.active.recent.to_a
    @recent = runs.where.not(id: @active.map(&:id)).recent.limit(10).to_a
    @worker = Agents::WorkerHealth.new
    @spend = Agents::Spend.summary
  end
end
