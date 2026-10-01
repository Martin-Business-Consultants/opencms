# frozen_string_literal: true

# Tools › Schedules: every recipe in ::RecurringTasks::Catalog (the core's and
# enabled plugins'), as a list table with each one's schedule and last run;
# its settings open in a sheet (#edit). :id is the
# recipe key; a recipe nobody has set up yet has no row until it's saved or run.
class Tools::RecurringTasksController < ApplicationController
  requires_capability "tools:use", only: [:index, :edit, :update]

  def index
    @recipes = ::RecurringTasks::Catalog.all
    @tasks = RecurringTask.all.index_by(&:recipe_key)
  end

  # A schedule's settings: into the list's sheet when it asked, otherwise the
  # list with the sheet open on it.
  def edit
    index
    @recipe = @recipes.find { it.key == params[:id] } or return redirect_to(tools_recurring_tasks_path, alert: "Unknown recipe.")
    return if turbo_frame_request?

    @sheet_recipe = @recipe
    render :index
  end

  def update
    @task = RecurringTask.find_or_initialize_by(recipe_key: params[:id])

    if !@task.recipe_class
      redirect_to tools_recurring_tasks_path, alert: "Unknown recipe."
    else
      @task.assign_attributes(task_params)
      if @task.save
        @task.track_event(:updated, recipe: @task.recipe_key, cron: @task.cron, enabled: @task.enabled)
        redirect_to tools_recurring_tasks_path, notice: "#{@task.recipe_class.title} saved."
      else
        index
        @tasks = @tasks.merge(@task.recipe_key => @task)
        @sheet_recipe = @recipes.find { it.key == @task.recipe_key }
        render :index, status: :unprocessable_content
      end
    end
  end

  private

  # Integer settings arrive as text from the form; the recipes read either,
  # but the API stores numbers, so these are stored the same way.
  def task_params
    permitted = params.require(:task).permit(:cron, :enabled, params: {})
    integers = Array(@task.recipe_class&.param_schema).select { it[:type] == "integer" }.map { it[:name].to_s }
    if permitted[:params]
      permitted[:params] = permitted[:params].to_h.to_h do |name, value|
        [name, integers.include?(name) && value.to_s.match?(/\A-?\d+\z/) ? value.to_i : value]
      end.compact_blank
    end
    permitted
  end
end
