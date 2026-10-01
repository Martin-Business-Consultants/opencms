# frozen_string_literal: true

# POST /api/invoices/:id/mark_paid
class Api::Invoices::PaymentsController < Api::BaseController
  include PluginGated
  plugin :commerce
  include InvoiceScoped

  enforce_authorization
  requires_capability "invoices:write", only: :create

  def create
    @invoice.mark_paid!
    render "api/invoices/show"
  end
end
