# frozen_string_literal: true

# One row per outbound webhook attempt. Append-only — the index page reads
# the most-recent few per webhook for a quick "is this thing healthy?" view.
# `payload` and `response_body` are truncated by Webhook::Deliverable to keep
# rows bounded.
class WebhookDelivery < ApplicationRecord
  belongs_to :webhook, inverse_of: :deliveries

  scope :recent, ->(n = 25) { order(created_at: :desc).limit(n) }
end
