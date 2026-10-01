# frozen_string_literal: true

# Sending an invoice: emails the customer the hosted page and payment link.
# Re-sending a sent invoice is allowed — a customer who lost the email gets
# it again.
class Invoices::DeliveriesController < ApplicationController
  include PluginGated
  plugin :commerce
  include InvoiceScoped

  requires_capability "invoices:send", only: :create

  def create
    if @invoice.sendable?
      @invoice.send!(base_url: request.base_url)
      redirect_to invoice_path(@invoice), notice: "Invoice #{@invoice.number} sent to #{@invoice.customer_email}"
    else
      redirect_to invoice_path(@invoice), alert: "An invoice needs a customer email and at least one line before it can be sent."
    end
  end
end
