# frozen_string_literal: true

# Updating the install from Settings › Updates: each update an admin
# started, how it ran (via) and how it went. The newest release itself is
# kept in the "updates" setting (UpdateCheck). A past update outlives the
# person who started it, so deleting them only blanks requested_by.
class CreateUpgrades < ActiveRecord::Migration[8.1]
  def change
    create_table :upgrades do |t|
      t.references :requested_by, foreign_key: {to_table: :users, on_delete: :nullify}
      t.string :from_version, null: false
      t.string :to_version, null: false
      t.string :via, null: false
      t.string :status, null: false, default: "running"
      t.string :external_id
      t.string :external_url
      t.text :message
      t.datetime :finished_at
      t.timestamps
    end
    add_index :upgrades, :status
  end
end
