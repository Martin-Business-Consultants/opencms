# frozen_string_literal: true

# The job's old name, kept so deliveries queued before Webhook::DeliveryJob
# replaced it still run. Remove once those have drained (one release).
class DeliverWebhookJob < Webhook::DeliveryJob
end
