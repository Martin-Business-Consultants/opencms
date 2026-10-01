# frozen_string_literal: true

# The scheduler's half: every minute (Agent::ScheduleJob), dispatch the agents
# whose cadence has come round. An agent with a run still in flight waits for
# its next turn rather than stacking a second one.
module Agent::Scheduled
  extend ActiveSupport::Concern

  class_methods do
    def dispatch_due(now = Time.current)
      due(now).find_each do |agent|
        next if agent.busy?

        agent.dispatch!(trigger: "schedule")
        agent.mark_enqueued!(at: now)
      end
    end
  end

  def busy?
    return false unless agent_runs.active.exists?

    Rails.logger.info("[agent-scheduler] skipping #{name} — a run is still active")
    true
  end
end
