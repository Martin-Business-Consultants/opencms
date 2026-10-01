# frozen_string_literal: true

# Scheduled maintenance recipes — Tools › Schedules over the API.
#
#   GET   /api/tools/recurring_tasks
#   PATCH /api/tools/recurring_tasks/:id           (:id is the recipe key)
#   POST  /api/tools/recurring_tasks/:id/run_now   (Api::Tools::RecurringTasks::RunsController)
#
# The index is the whole catalog, not just the configured rows: a recipe
# with no `task` has never been set up, and its `default_cron` /
# `param_schema` are what you'd configure it with.
class Api::Tools::RecurringTasksController < Api::BaseController
  include Api::RecurringTaskScoped

  enforce_authorization
  requires_capability "tools:use", only: [:index, :update]

  skip_before_action :set_recurring_task, only: :index

  def index
    @tasks = RecurringTask.all.index_by(&:recipe_key)
  end

  def update
    @task.update!(params.require(:task).permit(:cron, :enabled, params: {}))
    @task.track_event(:updated, recipe: @task.recipe_key, cron: @task.cron, enabled: @task.enabled)
    render :show
  end
end
