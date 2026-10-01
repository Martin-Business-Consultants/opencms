# frozen_string_literal: true

class CreateWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :webhooks do |t|
      t.string  :name,          null: false
      t.string  :url,           null: false
      t.json    :events,        null: false, default: []
      t.string  :secret,        null: false
      t.boolean :active,        null: false, default: true
      t.json    :headers,       null: false, default: {}
      t.integer :failure_count, null: false, default: 0
      t.string  :last_status
      t.datetime :last_delivery_at
      t.timestamps

      t.index :active
    end

    create_table :webhook_deliveries do |t|
      t.references :webhook, null: false, foreign_key: true
      t.string   :event,            null: false
      t.text     :payload,          null: false
      t.integer  :response_status
      t.text     :response_body
      t.text     :error
      t.integer  :duration_ms
      t.boolean  :success,          null: false, default: false
      t.datetime :created_at,       null: false

      t.index [:webhook_id, :created_at]
      t.index [:event, :created_at]
    end
  end
end
