# frozen_string_literal: true

# POST /api/invoices/:id/send — emails the customer (invoices:send).
class Api::Invoices::DeliveriesController < Api::BaseController
  include PluginGated
  plugin :commerce
  include InvoiceScoped

  enforce_authorization
  requires_capability "invoices:send", only: :create

  def create
    if @invoice.sendable?
      @invoice.send!(base_url: request.base_url)
      render "api/invoices/show"
    else
      render json: {error: "invalid", errors: {base: ["an invoice needs a customer email and at least one line to be sent"]}},
             status: :unprocessable_entity
    end
  end
end
