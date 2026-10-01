# frozen_string_literal: true

class CreateFormSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :form_submissions do |t|
      t.references :form, null: false, foreign_key: true
      t.json       :data, null: false, default: {}
      t.json       :meta, null: false, default: {}
      t.string     :ip
      t.timestamps

      t.index [:form_id, :created_at]
    end
  end
end
