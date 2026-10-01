# frozen_string_literal: true

class CreateRedirects < ActiveRecord::Migration[8.0]
  def change
    create_table :redirects do |t|
      t.string  :source_path,     null: false
      t.string  :destination_url, null: false
      t.integer :status_code,     null: false, default: 301
      t.boolean :active,          null: false, default: true
      t.boolean :wildcard,        null: false, default: false
      t.integer :hit_count,       null: false, default: 0
      t.datetime :last_hit_at
      t.text :notes
      t.timestamps

      t.index :source_path, unique: true
      t.index [:active, :wildcard]
    end
  end
end
