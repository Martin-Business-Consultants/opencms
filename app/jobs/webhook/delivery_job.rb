# frozen_string_literal: true

# Delivers one event to one webhook (Webhook::Deliverable#deliver_now).
# Retries are bounded — a misconfigured URL shouldn't fill the queue.
class Webhook::DeliveryJob < ApplicationJob
  queue_as :default

  retry_on Net::ReadTimeout,    wait: 30.seconds, attempts: 3
  retry_on Net::OpenTimeout,    wait: 30.seconds, attempts: 3
  retry_on Errno::ECONNREFUSED, wait: 30.seconds, attempts: 3

  # `_tenant` is only for jobs queued before this app became a single install;
  # it's ignored. Drop it once those have drained.
  def perform(webhook_id, event, payload, _tenant = nil)
    Webhook.find_by(id: webhook_id)&.deliver_now(event, payload)
  end
end
