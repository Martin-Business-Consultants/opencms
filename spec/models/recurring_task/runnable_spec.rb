# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringTask::Runnable do
  include ActiveJob::TestHelper

  it "sets up a never-configured task at its defaults when run on demand, and records it" do
    task = RecurringTask.find_or_initialize_by(recipe_key: "trash_purge")

    expect { task.run_on_demand }.to have_enqueued_job(RecurringTask::RunJob).with(kind_of(Integer))
    expect(task).to be_persisted
    expect(task.cron).to eq("0 3 * * *")
    expect(AuditLog.last).to have_attributes(action: "recurring_task.run_now", metadata: {"recipe" => "trash_purge"})
  end

  it "stamps the outcome of a run on the row" do
    task = RecurringTask.create!(recipe_key: "trash_purge", enabled: true)

    task.run_now

    expect(task.reload).to have_attributes(last_status: "ok", last_summary: "No records past retention.")
  end

  it "dispatches only the tasks that are due" do
    due = RecurringTask.create!(recipe_key: "trash_purge", enabled: true)
    due.update_column(:next_due_at, 1.minute.ago)
    RecurringTask.create!(recipe_key: "broken_link_scan", enabled: false)

    expect { RecurringTask.dispatch_due }.to have_enqueued_job(RecurringTask::RunJob).with(due.id).exactly(:once)
  end
end
