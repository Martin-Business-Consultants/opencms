# frozen_string_literal: true

class CreateSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :settings do |t|
      t.string :key,  null: false
      t.json   :data, null: false, default: {}
      t.timestamps

      t.index :key, unique: true
    end
  end
end
