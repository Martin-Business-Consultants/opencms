# frozen_string_literal: true

# The run log, for workers and scripts. The protocol that advances a run —
# claim, start, heartbeat, report, complete, fail, cancel — is one controller
# per step under Api::AgentRuns (see Api::AgentRunProtocol).
class Api::AgentRunsController < Api::BaseController
  include Api::AgentRunProtocol

  requires_capability "agents:read", only: [:index, :show]

  before_action :set_run, only: :show

  summarize_run :show

  def index
    runs = AgentRun.includes(:agent, :swarm).recent
    runs = runs.where(status: statuses) if statuses.any?
    runs = runs.where(claimed_by: params[:worker]) if params[:worker].present?
    @runs = runs.limit(limit)
  end

  def show
  end

  private

  def statuses
    Array(params[:status]).flat_map { |value| value.to_s.split(",") }.map(&:strip) & AgentRun::STATUSES
  end

  def limit = params[:limit].presence&.to_i&.clamp(1, 200) || 50
end
