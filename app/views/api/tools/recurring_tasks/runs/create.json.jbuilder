# frozen_string_literal: true

json.ok true
json.enqueued true
json.task do
  json.partial! "api/tools/recurring_tasks/task", record: @task
end
