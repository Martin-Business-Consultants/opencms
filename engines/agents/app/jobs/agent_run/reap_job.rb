# frozen_string_literal: true

# Every two minutes: give back runs whose worker went away (AgentRun.reap!).
class AgentRun::ReapJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    result = AgentRun.reap!(now: now)
    return if result.values.sum.zero?

    Rails.logger.info(
      "[agent-reaper] requeued=#{result[:requeued]} " \
      "failed=#{result[:failed]} expired=#{result[:expired]}"
    )
  end
end
