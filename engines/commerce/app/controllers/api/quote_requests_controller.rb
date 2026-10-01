# frozen_string_literal: true

# Public, unauthenticated endpoint a product page posts a "request a quote" to.
# The authenticated inbox is Api::QuotesController — same split as forms vs.
# submissions. Protections, in order: honeypot, per-IP rate limit, validation.
#
# Accepts JSON or form-encoded bodies:
#
#   {"customer_name": "…", "customer_email": "…", "customer_phone": "…",
#    "company": "…", "message": "…", "page_url": "https://…",
#    "items": [{"title": "…", "slug": "…", "sku": "…", "url": "…",
#               "unit_price": "$2,200.00", "quantity": 1}]}
class Api::QuoteRequestsController < Api::BaseController
  include PluginGated
  plugin :commerce
  include Api::PublicCors

  HONEYPOT_FIELD = "website"

  skip_before_action :authenticate_api, only: [:create, :options]
  before_action :set_cors_headers, only: [:create, :options]

  rate_limit to: 5, within: 10.minutes, only: :create,
    by:   -> { "quote_requests:#{request.ip}" },
    with: -> { render json: {error: "rate_limited"}, status: :too_many_requests }

  def create
    if params[HONEYPOT_FIELD].present?
      Rails.logger.info("[quotes] honeypot tripped ip=#{request.ip}")
      render :accepted, status: :created
      return
    end

    @quote = QuoteRequest.new(quote_params.merge(
      source: "site",
      ip:     request.ip,
      meta:   {user_agent: request.user_agent, referer: request.referer}
    ))

    if @quote.save
      render :create, status: :created
    else
      render json: {error: "invalid", errors: @quote.errors.to_hash}, status: :unprocessable_entity
    end
  end

  private

  def quote_params
    params.permit(:customer_name, :customer_email, :customer_phone, :company, :message, :page_url,
                  items: [:title, :slug, :sku, :url, :unit_price, :quantity])
  end
end
