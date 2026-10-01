# frozen_string_literal: true

# Agent definitions — the control-plane half of the agent system.
#
# The CMS does no inference. An agent here is *data*: instructions, the
# capabilities it may use, and a cadence. A local harness (installed by
# `agent/install.sh`) claims a run, executes the instructions with the `cms`
# CLI and the API, and reports back. So there are no built-in agent classes
# the way Lumin/ads has them — the starter set lives in
# `Agents::TemplateLibrary` and instantiates into an editable row, which
# gives the same "pick one, tune it" flow without a second code path.
#
# Cadence lives on the row rather than in a separate schedule table for the
# same reason: every agent is a row, so there is nothing to schedule that
# doesn't already have one.
class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.string  :name,             null: false
      t.text    :description
      t.string  :icon,             null: false, default: "sparkles"
      t.text    :instructions,     null: false
      t.json    :capability_keys,  null: false, default: []
      t.string  :preferred_model
      # Which library preset this was built from, if any. Kept so the
      # templates panel can say "already installed" instead of offering a
      # duplicate.
      t.string  :template_key

      t.boolean  :enabled,     null: false, default: false
      t.string   :cron
      t.datetime :next_due_at
      t.datetime :last_enqueued_at
      t.datetime :last_run_at

      t.timestamps

      t.index :name, unique: true
      t.index :template_key
      t.index [:enabled, :next_due_at]
    end

    # A reusable blueprint. Doesn't run; you instantiate it into an Agent.
    create_table :agent_templates do |t|
      t.string  :name,            null: false
      t.string  :category
      t.text    :description
      t.string  :icon,            null: false, default: "sparkles"
      t.text    :instructions,    null: false
      t.json    :capability_keys, null: false, default: []
      t.string  :preferred_model
      t.string  :cron
      # Set for rows seeded from Agents::TemplateLibrary, so a re-seed
      # updates the shipped copy instead of duplicating it. Null for
      # templates a tenant wrote itself.
      t.string  :template_key

      t.timestamps

      t.index :name, unique: true
      t.index :template_key, unique: true
      t.index :category
    end
  end
end
