# frozen_string_literal: true

class CreateForms < ActiveRecord::Migration[8.0]
  def change
    create_table :forms do |t|
      t.string  :slug,            null: false
      t.string  :title,           null: false
      t.string  :status,          null: false, default: "draft"
      t.json    :fields,          null: false, default: []
      t.string  :submit_url
      t.string  :submit_label,    null: false, default: "Submit"
      t.text    :success_message
      t.timestamps

      t.index :slug, unique: true
    end
  end
end
