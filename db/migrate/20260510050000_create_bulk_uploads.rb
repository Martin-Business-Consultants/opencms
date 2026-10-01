# frozen_string_literal: true

class CreateBulkUploads < ActiveRecord::Migration[8.0]
  def change
    create_table :bulk_uploads do |t|
      t.bigint  :user_id
      t.string  :folder, null: false, default: "/"
      t.string  :status, null: false, default: "pending"
      t.integer :total,     null: false, default: 0
      t.integer :processed, null: false, default: 0
      t.integer :succeeded, null: false, default: 0
      t.integer :skipped,   null: false, default: 0
      t.integer :failed,    null: false, default: 0
      t.json    :errors_log, null: false, default: []
      t.timestamps
    end
    add_index :bulk_uploads, :status
    add_index :bulk_uploads, :user_id
  end
end
