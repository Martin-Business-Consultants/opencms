# frozen_string_literal: true

# Voiding an invoice: it stays on record, crossed out, and can't be paid.
class Invoices::VoidingsController < ApplicationController
  include PluginGated
  plugin :commerce
  include InvoiceScoped

  requires_capability "invoices:write", only: :create

  def create
    @invoice.void!
    redirect_to invoice_path(@invoice), notice: "Invoice #{@invoice.number} voided"
  end
end
