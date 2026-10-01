# frozen_string_literal: true

class CreateBlockTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :block_types do |t|
      t.string  :slug,         null: false
      t.string  :label,        null: false
      t.string  :description
      t.string  :icon
      t.string  :category
      t.json    :fields,       null: false, default: []
      t.integer :version,      null: false, default: 1
      t.boolean :built_in,     null: false, default: false
      t.timestamps

      t.index :slug, unique: true
      t.index :category
    end
  end
end
