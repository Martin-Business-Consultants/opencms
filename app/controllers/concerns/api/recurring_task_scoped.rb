# frozen_string_literal: true

# The task a /api/tools/recurring_tasks/:id route names, by recipe key. A
# recipe that was never configured has no row yet, so it's built at its
# defaults; an unknown key is a 404 listing the ones there are.
module Api::RecurringTaskScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_recurring_task
  end

  private

  def set_recurring_task
    @task = RecurringTask.find_or_initialize_by(recipe_key: params[:recurring_task_id] || params[:id])
    return if @task.recipe_class

    render json: {error: "not_found", message: "Unknown recipe #{@task.recipe_key.inspect} — known recipes: #{RecurringTasks::Catalog.all.map(&:key).join(", ")}"}, status: :not_found
  end
end
