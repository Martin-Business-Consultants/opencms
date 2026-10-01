# frozen_string_literal: true

# Tools › Schedules › Run now: queues one run of a recipe (RecurringTask#run_on_demand).
class Tools::RecurringTasks::RunsController < ApplicationController
  requires_capability "tools:use", only: :create

  def create
    task = RecurringTask.find_or_initialize_by(recipe_key: params[:recurring_task_id])

    if task.recipe_class
      task.run_on_demand
      redirect_to tools_recurring_tasks_path, notice: "#{task.recipe_class.title} queued."
    else
      redirect_to tools_recurring_tasks_path, alert: "Unknown recipe."
    end
  end
end
