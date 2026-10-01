# frozen_string_literal: true

# Per-event filter config for webhooks. Today this only narrows
# `submission.created` deliveries to a chosen set of forms; the column is
# event-keyed so future events can carry their own criteria without a new
# migration. Shape: { "<event>" => { "<criterion>" => <value> } }.
class AddEventFiltersToWebhooks < ActiveRecord::Migration[8.0]
  def change
    add_column :webhooks, :event_filters, :json, null: false, default: {}
  end
end
