# frozen_string_literal: true

json.webhooks @webhooks, partial: "api/webhooks/webhook", as: :record
json.events Webhook.events
