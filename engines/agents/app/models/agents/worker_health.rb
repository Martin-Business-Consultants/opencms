# frozen_string_literal: true

module Agents
  # "Is anything out there to run this?", answered from the runs themselves
  # rather than a worker registry: a box that claimed work in the last
  # quarter hour is a box that exists, and nothing else needs maintaining to
  # stay true. The other way to run the roster is in-process, on the AI
  # plugin's key (Agents::Runner).
  class WorkerHealth
    RECENT = 15.minutes

    def last_claim_at
      return @last_claim_at if defined?(@last_claim_at)

      @last_claim_at = AgentRun.where.not(claimed_at: nil).maximum(:claimed_at)
    end

    def seen_recently? = last_claim_at.present? && last_claim_at > RECENT.ago
    def queued = @queued ||= AgentRun.where(status: "queued").count
    def active = @active ||= AgentRun.active.count

    # A key saved in the AI plugin runs dispatched runs here.
    def in_process? = Cms::Plugins.provided(:ai)&.configured? || false
    def executor = in_process? ? "in-process" : "worker"
    def default_model = Ai::Models.label(Ai::Models.default_tier)

    # The hash Agents::RosterState reads.
    def to_h
      {last_claim_at: last_claim_at&.iso8601, seen_recently: seen_recently?, queued: queued, active: active,
       zen_configured: in_process?, executor: executor, default_model: default_model}
    end
  end
end
