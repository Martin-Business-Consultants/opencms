# frozen_string_literal: true

# Every minute (config/recurring.yml): runs the tasks that are due.
class RecurringTask::DispatchJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current) = RecurringTask.dispatch_due(now)
end
