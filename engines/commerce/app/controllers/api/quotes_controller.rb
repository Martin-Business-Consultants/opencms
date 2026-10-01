# frozen_string_literal: true

# The quote inbox, authenticated: what the shop reads and works. The public
# write path is Api::QuoteRequestsController.
#
#   GET    /api/quotes?status=new&since=…&page=1&per=25
#   GET    /api/quotes/:id
#   POST   /api/quotes                 — a request typed in by staff or an agent
#   PATCH  /api/quotes/:id             — status, notes, contact details
#   DELETE /api/quotes/:id
class Api::QuotesController < Api::BaseController
  include PluginGated
  plugin :commerce

  enforce_authorization
  requires_capability "quotes:read",   only: [:index, :show]
  requires_capability "quotes:write",  only: [:create, :update]
  requires_capability "quotes:delete", only: [:destroy]

  before_action :set_quote, only: [:show, :update, :destroy]

  agent_summary(:index) do |payload|
    total = payload["total"].to_i
    open  = payload.dig("counts", "new").to_i
    "#{total} quote #{"request".pluralize(total)}#{open.positive? ? ", #{open} new" : ""}."
  end
  agent_breadcrumbs(:index) do |payload|
    first = payload.dig("quotes", 0, "id")
    [first ? crumb("Open one", "cms quote #{first}") : nil,
     first ? crumb("Bill it", "cms invoice-create --from-quote #{first}") : nil].compact
  end
  agent_breadcrumbs(:show) do |payload|
    id = payload.dig("quote", "id")
    [crumb("Mark it quoted", "cms quote-status #{id} quoted"),
     crumb("Draft an invoice from it", "cms invoice-create --from-quote #{id}")]
  end

  def index
    scope = QuoteRequest.ordered
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("created_at >= ?", parse_time(params[:since])) if params[:since].present?

    @page_number = (params[:page] || 1).to_i.clamp(1, 10_000)
    @per         = (params[:per]  || 25).to_i.clamp(1, 100)
    @counts      = QuoteRequest.status_counts
    @total       = scope.count
    @quotes      = scope.offset((@page_number - 1) * @per).limit(@per)
  end

  def show
  end

  def create
    @quote = QuoteRequest.new(quote_params.merge(source: "api"))
    @quote.save!
    @quote.track_event(:created)
    render :show, status: :created
  end

  def update
    @quote.update!(quote_params)
    @quote.track_event(:updated, fields: quote_params.keys)
    render :show
  end

  def destroy
    @quote.track_event(:deleted)
    @quote.destroy!
    head :no_content
  end

  private

  def set_quote
    @quote = QuoteRequest.find(params[:id])
  end

  def quote_params
    params.require(:quote).permit(:customer_name, :customer_email, :customer_phone, :company,
                                  :message, :status, :notes, :page_url,
                                  items: [:title, :slug, :sku, :url, :unit_price, :quantity])
  end

  def parse_time(value)
    Time.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
