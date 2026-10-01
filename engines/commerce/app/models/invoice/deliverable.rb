# frozen_string_literal: true

# Emailing the invoice to the customer, with a link to its hosted page under
# base_url. #send! marks it sent and queues this.
module Invoice::Deliverable
  extend ActiveSupport::Concern

  def deliver_later(base_url)
    Invoice::DeliveryJob.perform_later(id, base_url)
  end

  def deliver_now(base_url)
    return if customer_email.blank?

    InvoiceMailer.with(invoice: self, base_url: base_url).deliver.deliver_now
  end
end
