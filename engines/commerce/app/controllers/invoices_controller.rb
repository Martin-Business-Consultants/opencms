# frozen_string_literal: true

# Commerce › Invoices: drafted from a quote request (or from scratch), given a
# payment link, sent to the customer, marked paid. Sending, paying and voiding
# are resources under Invoices::.
class InvoicesController < ApplicationController
  include PluginGated
  plugin :commerce

  requires_capability "invoices:read",   only: [:index, :show]
  requires_capability "invoices:write",  only: [:new, :create, :edit, :update]
  requires_capability "invoices:delete", only: [:destroy]

  before_action :set_invoice, only: [:show, :edit, :update, :destroy]

  def index
    @status = params[:status].presence_in(Invoice::STATUSES)
    @counts = Invoice.group(:status).count
    scope = Invoice.ordered.includes(:quote_request).search_list(search_term)
    scope = scope.where(status: @status) if @status
    @invoices = paginate(scope)
  end

  def show
  end

  def new
    @invoice = if params[:quote_request_id].present?
      Invoice.from_quote_request(QuoteRequest.find(params[:quote_request_id]))
    else
      Invoice.drafted
    end
  end

  def create
    @invoice = Invoice.new(invoice_params)

    if @invoice.save
      @invoice.quote_request&.update(status: "quoted") if @invoice.quote_request&.status == "new"
      @invoice.track_event(:created, number: @invoice.number)
      redirect_to invoice_path(@invoice), notice: "Invoice #{@invoice.number} drafted"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    attrs = invoice_params
    if @invoice.update(attrs)
      @invoice.track_event(:updated, fields: attrs.keys)
      redirect_to invoice_path(@invoice), notice: "Invoice #{@invoice.number} saved"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @invoice.draft?
      @invoice.track_event(:deleted, number: @invoice.number)
      @invoice.destroy!
      redirect_to invoices_path, notice: "Draft #{@invoice.number} deleted"
    else
      redirect_to invoice_path(@invoice), alert: "Only drafts can be deleted. Void a sent invoice instead."
    end
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  end

  # The form posts amounts as people type them ("$1,250.00") and lines as
  # rows keyed by an opaque id (the schema editor's); the model wants cents
  # and a list.
  def invoice_params
    raw = params.require(:invoice)
    raw[:line_items] = raw[:line_items].values if raw[:line_items].respond_to?(:values)

    attrs = raw.permit(:quote_request_id, :customer_name, :customer_email, :customer_phone, :company, :billing_address,
      :currency, :tax, :shipping, :payment_link, :notes, :terms, :issued_on, :due_on,
      line_items: [:description, :sku, :quantity, :unit_price])
    attrs[:tax_cents] = MoneyCents.parse(attrs.delete(:tax)).to_i if attrs.key?(:tax)
    attrs[:shipping_cents] = MoneyCents.parse(attrs.delete(:shipping)).to_i if attrs.key?(:shipping)
    # The form always sends the marker, so removing every line saves none.
    attrs[:line_items] ||= [] if raw.key?(:lines_sent)
    attrs
  end
end
