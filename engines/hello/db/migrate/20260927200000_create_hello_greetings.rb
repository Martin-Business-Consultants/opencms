# frozen_string_literal: true

class CreateHelloGreetings < ActiveRecord::Migration[8.1]
  def change
    create_table :hello_greetings do |t|
      t.string :message, null: false
      t.references :user, foreign_key: true
      t.timestamps
    end
  end
end
