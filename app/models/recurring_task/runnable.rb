# frozen_string_literal: true

# Running a task: every minute the due ones are dispatched
# (RecurringTask.dispatch_due), each run goes through a job, and a run
# stamps its outcome on the row so Tools › Schedules can show it. Bumping
# `last_run_at` recomputes `next_due_at`, which schedules the next firing.
module RecurringTask::Runnable
  extend ActiveSupport::Concern

  class_methods do
    def dispatch_due(now = Time.current)
      due(now).find_each(&:run_later)
    end
  end

  # "Run now" from Tools › Schedules or the API. A recipe that has never been
  # configured gets a row at its defaults first, so there's something to
  # stamp the result on.
  def run_on_demand
    if new_record?
      self.cron = recipe_class.default_cron
      self.params = recipe_class.default_params
      save!
    end

    run_later
    track_event(:run_now, recipe: recipe_key)
  end

  def run_later
    RecurringTask::RunJob.perform_later(id)
  end

  # Recipe errors are caught and stamped onto the row rather than raised.
  def run_now
    return unless enabled && RecurringTasks::Catalog.known?(recipe_key)

    started = Time.current
    update_columns(last_status: "running", updated_at: started)

    begin
      summary = RecurringTasks::Catalog.fetch(recipe_key, params || {}).perform.to_s
      update!(last_run_at: started, last_status: "ok", last_summary: summary.truncate(1_000), last_error: nil,
        last_duration_ms: ((Time.current - started) * 1000).round)
    rescue StandardError => e
      Rails.logger.error("[recurring-task] #{recipe_key} #{e.class}: #{e.message}")
      update!(last_run_at: started, last_status: "error", last_summary: nil,
        last_error: "#{e.class}: #{e.message}".truncate(1_000), last_duration_ms: ((Time.current - started) * 1000).round)
    end
  end
end
