# frozen_string_literal: true

# One execution of an agent against this site, performed by a local harness.
#
# The server never runs the model. It queues a run, hands out a frozen brief
# when a worker claims it, and records what came back. That inverts the
# staleness rule Lumin/ads learned the hard way: a `queued` run with no
# worker is WAITING, not stale, so only a *claimed* run whose lease expired
# gets requeued. Solid Queue is up whenever the app is; a worker box is not.
#
# `brief` is a snapshot taken at dispatch — instructions, capabilities and
# scope as they were then. Editing an agent afterwards changes what its next
# run does, never what a finished run says it did.
class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_runs do |t|
      # Nullified rather than cascaded: a deleted agent shouldn't erase the
      # record of the work it did, so the name is denormalized alongside.
      t.references :agent,        null: true, foreign_key: {on_delete: :nullify}
      t.string     :agent_name,   null: false
      t.references :swarm,        null: true, foreign_key: {on_delete: :nullify}
      t.references :swarm_member, null: true, foreign_key: {on_delete: :nullify}
      t.references :triggered_by, null: true

      t.string :status,  null: false, default: "queued"
      t.string :trigger, null: false, default: "manual"

      t.json :brief, null: false, default: {}

      # Lease, not timeout. A claimed run whose lease lapses goes back to
      # `queued` with attempts += 1 rather than failing outright — a worker
      # rebooting mid-run is an interruption, not an error.
      t.string   :claimed_by
      t.datetime :claimed_at
      t.datetime :lease_expires_at
      t.integer  :attempts, null: false, default: 0

      t.datetime :started_at
      t.datetime :finished_at
      t.boolean  :cancel_requested, null: false, default: false

      t.text :summary
      t.text :error
      # Append-only progress the harness reports as it works, so a run in
      # flight is legible without the worker holding a socket open.
      t.json :transcript, null: false, default: []

      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :priority, null: false, default: 0
      # Drop rather than backlog: a run nobody claimed for a day is almost
      # always a worker that never came back, and running it now would act on
      # a site that has since moved.
      t.datetime :expires_at

      t.timestamps

      # The claim query: oldest queued run of the highest priority.
      t.index [:status, :priority, :created_at], name: "idx_agent_runs_on_claim"
      t.index :lease_expires_at
      t.index [:agent_id, :created_at]
      t.index [:swarm_id, :created_at]
    end
  end
end
