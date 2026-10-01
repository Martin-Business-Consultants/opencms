# frozen_string_literal: true

# The invoice a nested resource acts on (Invoices::DeliveriesController…).
# The admin's routes name it :invoice_id; the API's keep their old :id.
module InvoiceScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_invoice
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:invoice_id] || params[:id])
  end
end
