# frozen_string_literal: true

# The built-in AI assistant is gone: agents now drive the CMS from the
# outside through the API and the `cms` CLI, so there is no server-side
# generation to audit. This table only ever held proposals produced by that
# assistant, and nothing reads it any more.
class DropAiProposals < ActiveRecord::Migration[8.0]
  def up
    drop_table :ai_proposals, if_exists: true
  end

  # Mirrors CreateAiProposals so a rollback lands on the original schema.
  # The rows themselves are gone for good.
  def down
    create_table :ai_proposals do |t|
      t.string  :intent,      null: false
      t.string  :model
      t.text    :prompt,      null: false
      t.string  :target_type
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
