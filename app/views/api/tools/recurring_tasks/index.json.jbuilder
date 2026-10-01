# frozen_string_literal: true

json.recipes RecurringTasks::Catalog.all do |recipe|
  json.key recipe.key
  json.title recipe.title
  json.description recipe.description
  json.default_cron recipe.default_cron
  json.param_schema recipe.param_schema
  if (task = @tasks[recipe.key])
    json.task { json.partial! "api/tools/recurring_tasks/task", record: task }
  else
    json.task nil
  end
end
