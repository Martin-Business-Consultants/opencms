# frozen_string_literal: true

class AgentRun::ExecutionJob < ApplicationJob
  queue_as :default

  # `_tenant`: jobs queued before single installs carry a trailing tenant.
  def perform(run_id, _tenant = nil)
    AgentRun.find_by(id: run_id)&.execute_now
  end
end
