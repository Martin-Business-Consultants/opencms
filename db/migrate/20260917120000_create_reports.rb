# frozen_string_literal: true

# One stored run of one report — the answer DataForSEO gave, on a date, for
# what it cost.
#
# Snapshots rather than a live proxy, for three reasons. The calls are slow
# (up to 120s for LLM mentions) and would block a page render; they cost real
# money per call, so a page refresh must not be a purchase; and the value of
# this data is almost entirely in the comparison — "are we in the map pack
# now" matters much less than "we were, in March". A cache would give the
# first two and throw away the third.
#
# `data` holds the normalized result, not the raw response. See
# Reports::Definition: the raw envelopes run to hundreds of KB of mostly
# irrelevant JSON, and storing them would trade a readable history for a
# large one.
class CreateReports < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.string :kind, null: false

      t.string :status, null: false, default: "queued"

      # The Profile as it was when the report ran. Denormalized on purpose:
      # a report run against the old tracked-keyword list is still a true
      # record of that run, and re-reading today's settings to render it
      # would silently relabel history.
      t.json :params, null: false, default: {}

      # The normalized result. Shape is per-report; see the definition.
      t.json :data, null: false, default: {}

      # What DataForSEO actually charged, in USD. Stored as a string-backed
      # decimal because these are fractions of a cent and floats accumulate
      # error over a year of weekly runs.
      t.decimal :cost, precision: 10, scale: 6, null: false, default: 0.0

      t.text :error

      # Null for a scheduled run — nobody asked, the cron did.
      t.references :requested_by, null: true

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps

      # The index that matters: "the latest report of each kind" is the
      # index page's only query, and it runs on every page load.
      t.index [:kind, :created_at]
      t.index [:kind, :status, :created_at]
    end
  end
end
