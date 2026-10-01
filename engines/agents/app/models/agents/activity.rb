# frozen_string_literal: true

module Agents
  # The last 30 days of runs, by outcome, said in words (charts may come back
  # with the reporting redesign). `scope` narrows it (one swarm's runs).
  class Activity
    WINDOW = 30.days

    def initialize(scope = AgentRun.all)
      @counts = scope.where(created_at: WINDOW.ago..).group(:status).count
    end

    def completed = @counts["completed"].to_i
    def failed = @counts["failed"].to_i
    def canceled = @counts["canceled"].to_i
    def active = @counts.values_at("queued", "claimed", "running").sum(&:to_i)
    def total = @counts.values.sum
    def days = WINDOW.in_days.to_i
  end
end
