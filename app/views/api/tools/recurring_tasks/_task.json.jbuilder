# frozen_string_literal: true

json.extract! record, :id, :recipe_key, :cron, :params, :enabled, :next_due_at,
  :last_run_at, :last_status, :last_summary, :last_error, :last_duration_ms
