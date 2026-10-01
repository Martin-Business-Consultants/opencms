# frozen_string_literal: true

# POST /api/tools/recurring_tasks/:id/run_now — queues an immediate run,
# the same as the admin's Run now button.
class Api::Tools::RecurringTasks::RunsController < Api::BaseController
  include Api::RecurringTaskScoped

  enforce_authorization
  requires_capability "tools:use", only: [:create]

  def create
    @task.run_on_demand
    render status: :accepted
  end
end
