# frozen_string_literal: true

# Per-tenant recurring task definitions. Each row pairs a `recipe_key`
# (lookup into RecurringTasks::Catalog) with a cron expression and a small
# set of recipe-specific params. The dispatcher job walks all tenants every
# minute, finds enabled tasks whose `next_due_at` has passed, and enqueues
# a runner per task.
class CreateRecurringTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :recurring_tasks do |t|
      t.string  :recipe_key,      null: false
      t.string  :cron,            null: false, default: ""
      t.json    :params,          null: false, default: {}
      t.boolean :enabled,         null: false, default: false
      t.datetime :next_due_at
      t.datetime :last_run_at
      t.string  :last_status                  # "ok" | "error" | "running"
      t.text    :last_summary
      t.text    :last_error
      t.integer :last_duration_ms
      t.timestamps

      t.index :recipe_key, unique: true
      t.index [:enabled, :next_due_at]
    end
  end
end
