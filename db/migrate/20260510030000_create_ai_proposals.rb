# frozen_string_literal: true

class CreateAiProposals < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_proposals do |t|
      t.string  :intent,      null: false
      t.string  :model
      t.text    :prompt,      null: false
      t.string  :target_type           # nil for create_* intents
      t.string  :target_slug
      t.string  :target_collection
      t.json    :proposal,    null: false, default: {}
      t.text    :error
      t.references :user,     foreign_key: true
      t.datetime :accepted_at
      t.references :accepted_by, foreign_key: {to_table: :users}
      t.timestamps

      t.index [:intent, :created_at]
      t.index [:target_type, :target_slug]
    end
  end
end
