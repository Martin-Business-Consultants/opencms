# frozen_string_literal: true

json.task do
  json.partial! "api/tools/recurring_tasks/task", record: @task
end
