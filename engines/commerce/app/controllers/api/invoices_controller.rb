# frozen_string_literal: true

# Invoices over the API — the surface behind `cms invoices` / `cms invoice`.
#
#   GET    /api/invoices?status=sent
#   GET    /api/invoices/:id
#   POST   /api/invoices                      — {"invoice": {…}} or {"quote_request_id": 12}
#   PATCH  /api/invoices/:id
#   POST   /api/invoices/:id/send             — emails the customer (Api::Invoices::DeliveriesController)
#   POST   /api/invoices/:id/mark_paid        — Api::Invoices::PaymentsController
#   POST   /api/invoices/:id/void             — Api::Invoices::VoidingsController
#   DELETE /api/invoices/:id                  — drafts only
class Api::InvoicesController < Api::BaseController
  include PluginGated
  plugin :commerce

  enforce_authorization
  requires_capability "invoices:read",   only: [:index, :show]
  requires_capability "invoices:write",  only: [:create, :update]
  requires_capability "invoices:delete", only: [:destroy]

  before_action :set_invoice, only: [:show, :update, :destroy]

  agent_summary(:index) { |payload| "#{payload["total"].to_i} #{"invoice".pluralize(payload["total"].to_i)}." }
  agent_breadcrumbs(:index) do |payload|
    first = payload.dig("invoices", 0, "id")
    [first ? crumb("Open one", "cms invoice #{first}") : nil].compact
  end
  agent_breadcrumbs(:show, :create, :update) do |payload|
    inv = payload["invoice"] || {}
    crumbs = []
    crumbs << crumb("Set the payment link", "cms patch /invoices/#{inv["id"]} '{\"invoice\":{\"payment_link\":\"https://…\"}}'") if inv["payment_link"].blank?
    crumbs << crumb("Send it to the customer", "cms invoice-send #{inv["id"]}") if inv["status"] == "draft"
    crumbs << crumb("Mark it paid", "cms invoice-paid #{inv["id"]}") if inv["status"] == "sent"
    crumbs
  end

  def index
    scope = Invoice.ordered
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(quote_request_id: params[:quote_request_id]) if params[:quote_request_id].present?

    @page_number = (params[:page] || 1).to_i.clamp(1, 10_000)
    @per         = (params[:per]  || 25).to_i.clamp(1, 100)
    @total       = scope.count
    @invoices    = scope.offset((@page_number - 1) * @per).limit(@per)
  end

  def show
  end

  # Two ways in: a full invoice body, or a quote to prefill from (with an
  # optional body on top — say a corrected price).
  def create
    @invoice = if params[:quote_request_id].present?
      Invoice.from_quote_request(QuoteRequest.find(params[:quote_request_id]))
    else
      Invoice.new
    end
    @invoice.assign_attributes(invoice_params) if params[:invoice].present?
    @invoice.save!
    @invoice.quote_request&.update(status: "quoted") if @invoice.quote_request&.status == "new"
    @invoice.track_event(:created, number: @invoice.number)
    render :show, status: :created
  end

  def update
    @invoice.update!(invoice_params)
    @invoice.track_event(:updated, fields: invoice_params.keys)
    render :show
  end

  def destroy
    if @invoice.draft?
      @invoice.track_event(:deleted, number: @invoice.number)
      @invoice.destroy!
      head :no_content
    else
      render json: {error: "invalid", errors: {base: ["only drafts can be deleted; void a sent invoice instead"]}},
             status: :unprocessable_entity
    end
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  end

  def invoice_params
    params.require(:invoice).permit(
      :customer_name, :customer_email, :customer_phone, :company, :billing_address,
      :currency, :tax_cents, :shipping_cents, :payment_link, :notes, :terms, :issued_on, :due_on,
      :quote_request_id,
      line_items: [:description, :sku, :quantity, :unit_price_cents, :unit_price]
    )
  end
end
