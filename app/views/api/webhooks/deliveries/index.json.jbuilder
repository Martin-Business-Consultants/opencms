# frozen_string_literal: true

json.deliveries @deliveries, partial: "api/webhooks/delivery", as: :record
