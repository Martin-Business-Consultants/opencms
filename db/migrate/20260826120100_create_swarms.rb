# frozen_string_literal: true

# Swarms — a standing team of agents that work the site on a determinate
# rota, each member with its own cadence and model.
#
# `content_scopes` is one polymorphic table rather than the two parallel
# target tables Lumin/ads carries. Scoping means the same thing wherever it
# is attached — "which part of this site" — so a single shape keeps the
# model, the form and the resolver in one place, and an agent stays scopeable
# everywhere a swarm is.
class CreateSwarms < ActiveRecord::Migration[8.1]
  def change
    create_table :swarms do |t|
      t.string  :name,        null: false
      t.text    :description
      t.string  :icon,        null: false, default: "users"
      t.boolean :enabled,     null: false, default: false
      t.string  :template_key

      t.timestamps

      t.index :name, unique: true
      t.index :template_key
    end

    create_table :swarm_members do |t|
      t.references :swarm, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.string  :role
      t.string  :model
      t.integer :position,  null: false, default: 0
      t.boolean :enabled,   null: false, default: true

      # Determinate rota: fire when the current day+hour match.
      t.string  :frequency, null: false, default: "weekly"
      t.integer :day,       null: false, default: 1
      t.integer :hour,      null: false, default: 9
      t.datetime :last_enqueued_at

      t.timestamps

      # One seat per agent per swarm — the same agent twice in a roster is a
      # mistake that shows up as duplicate runs, not as an error.
      t.index [:swarm_id, :agent_id], unique: true
    end

    create_table :swarm_templates do |t|
      t.string :name,     null: false
      t.string :category
      t.text   :description
      t.string :icon,     null: false, default: "users"
      # Roster rows: [{template_key/agent_name, role, model, frequency, day, hour}, …].
      # Members name an agent TEMPLATE, not an agent row: a swarm template has
      # to be standable-up on a tenant that has never created an agent, and
      # instantiating it can then create the agents it needs.
      t.json   :members,  null: false, default: []
      t.string :template_key

      t.timestamps

      t.index :name, unique: true
      t.index :template_key, unique: true
      t.index :category
    end

    # What an agent or swarm works: the whole site, a collection, a path
    # prefix, or a locale. No rows means the whole site.
    create_table :content_scopes do |t|
      t.references :scopable, polymorphic: true, null: false
      t.string :scope_kind, null: false, default: "site"
      t.string :value

      t.timestamps

      t.index [:scopable_type, :scopable_id, :scope_kind, :value],
              unique: true, name: "idx_content_scopes_unique"
    end
  end
end
