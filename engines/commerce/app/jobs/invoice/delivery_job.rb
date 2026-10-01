# frozen_string_literal: true

class Invoice::DeliveryJob < ApplicationJob
  queue_as :default

  # The splat takes the tenant that jobs queued before single installs carry
  # between the id and the base URL.
  def perform(invoice_id, *, base_url)
    Invoice.find_by(id: invoice_id)&.deliver_now(base_url)
  end
end
