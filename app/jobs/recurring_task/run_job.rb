# frozen_string_literal: true

# One run of a RecurringTask (RecurringTask#run_now).
class RecurringTask::RunJob < ApplicationJob
  queue_as :default

  # The trailing keywords are only for jobs queued before this app became a
  # single install (they carried a tenant); they're ignored.
  def perform(task_id, **) = RecurringTask.find_by(id: task_id)&.run_now
end
