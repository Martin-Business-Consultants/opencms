# frozen_string_literal: true

# Commerce › Quote requests: the inbox of "what does this cost?" from the site.
# Bulk delete is QuoteRequests::BulkDeletionsController; drafting an invoice
# from a request is InvoicesController#new.
class QuoteRequestsController < ApplicationController
  include PluginGated
  plugin :commerce

  requires_capability "quotes:read",   only: [:index, :show]
  requires_capability "quotes:write",  only: [:update]
  requires_capability "quotes:delete", only: [:destroy]

  before_action :set_quote, only: [:show, :update, :destroy]

  def index
    @status = params[:status].presence_in(QuoteRequest::STATUSES)
    @counts = QuoteRequest.status_counts
    scope = QuoteRequest.ordered.includes(:invoices).search_list(search_term)
    scope = scope.where(status: @status) if @status
    @quotes = paginate(scope)
  end

  def show
    @invoices = @quote.invoices.ordered
  end

  def update
    if @quote.update(quote_params)
      @quote.track_event(:updated, fields: quote_params.keys)
      redirect_to quote_request_path(@quote), notice: "Quote request updated"
    else
      @invoices = @quote.invoices.ordered
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @quote.track_event(:deleted)
    @quote.destroy!
    redirect_to quote_requests_path, notice: "Quote request deleted"
  end

  private

  def set_quote
    @quote = QuoteRequest.find(params[:id])
  end

  def quote_params
    params.require(:quote).permit(:status, :notes, :customer_name, :customer_email, :customer_phone, :company)
  end
end
