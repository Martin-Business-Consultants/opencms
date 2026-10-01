# frozen_string_literal: true

# Running in this process. When the site holds a Zen key a queued run executes
# here, in a job (Agents::Runner); without one it stays queued for a worker
# box to claim through the API. #execute_now re-checks both at execution time,
# so a key removed mid-queue degrades back to the worker path.
module AgentRun::Executable
  extend ActiveSupport::Concern

  def execute_later
    AgentRun::ExecutionJob.perform_later(id)
  end

  def execute_now
    return unless Ai::Zen.configured? && queued?

    Agents::Runner.perform(self)
  end
end
