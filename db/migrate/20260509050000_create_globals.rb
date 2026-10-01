# frozen_string_literal: true

class CreateGlobals < ActiveRecord::Migration[8.0]
  def change
    create_table :globals do |t|
      t.string  :slug,        null: false
      t.string  :name,        null: false
      t.string  :description
      t.string  :icon
      t.json    :schema,      null: false, default: {}
      t.json    :data,        null: false, default: {}
      t.integer :version,     null: false, default: 1
      t.timestamps

      t.index :slug, unique: true
    end
  end
end
