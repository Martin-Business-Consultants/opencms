# frozen_string_literal: true

json.webhook do
  json.partial! "api/webhooks/webhook", record: @webhook, with_secret: true
end
