# frozen_string_literal: true

# Every minute: queue the agents and swarm seats that are due. Nothing here
# runs a model.
class Agent::ScheduleJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    Agent.dispatch_due(now)
    Swarm.dispatch_all_due(now)
  end
end
