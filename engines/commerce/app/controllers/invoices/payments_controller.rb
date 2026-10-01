# frozen_string_literal: true

# Marking an invoice paid (the money moved through the shop's processor).
class Invoices::PaymentsController < ApplicationController
  include PluginGated
  plugin :commerce
  include InvoiceScoped

  requires_capability "invoices:write", only: :create

  def create
    @invoice.mark_paid!
    redirect_to invoice_path(@invoice), notice: "Invoice #{@invoice.number} marked paid"
  end
end
