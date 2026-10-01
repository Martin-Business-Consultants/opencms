# frozen_string_literal: true

# POST /api/invoices/:id/void
class Api::Invoices::VoidingsController < Api::BaseController
  include PluginGated
  plugin :commerce
  include InvoiceScoped

  enforce_authorization
  requires_capability "invoices:write", only: :create

  def create
    @invoice.void!
    render "api/invoices/show"
  end
end
