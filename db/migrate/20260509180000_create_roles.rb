# frozen_string_literal: true

class CreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      t.string :name,        null: false, index: {unique: true}
      t.string :description

      t.timestamps
    end
  end
end
