# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api invoices", type: :request do
  let(:admin) { create(:user) }

  before { Cms::Plugins.switch!(:commerce, on: true) }

  def auth(capabilities = nil)
    actor = capabilities ? create(:user, admin: false, role: create(:role, permissions: capabilities)) : admin
    {"Authorization" => "Bearer #{actor.api_token.token}"}
  end

  def json = JSON.parse(response.body)

  let!(:quote) do
    QuoteRequest.create!(customer_name: "Jane Baker", customer_email: "jane@bakery.test",
      items: [{"title" => "Hobart A200", "sku" => "A200", "unit_price" => "$2,200.00", "quantity" => 1}])
  end

  it "drafts an invoice from a quote request, prefilled, and marks the quote quoted" do
    post "/api/invoices", params: {quote_request_id: quote.id, invoice: {payment_link: "https://buy.stripe.test/abc"}},
      as: :json, headers: auth(["invoices:write"])

    expect(response).to have_http_status(:created)
    inv = json["invoice"]
    expect(inv["customer_email"]).to eq("jane@bakery.test")
    expect(inv["line_items"].first).to include("description" => "Hobart A200", "unit_price_cents" => 220_000)
    expect(inv["total_cents"]).to eq(220_000)
    expect(inv["status"]).to eq("draft")
    expect(inv["public_url"]).to match(%r{/i/[A-Za-z0-9_-]+\z})
    expect(quote.reload.status).to eq("quoted")
  end

  it "requires invoices:send to send, and sends" do
    invoice = Invoice.from_quote_request(quote).tap(&:save!)

    post "/api/invoices/#{invoice.id}/send", headers: auth(["invoices:read", "invoices:write"])
    expect(response).to have_http_status(:forbidden)

    expect {
      post "/api/invoices/#{invoice.id}/send", headers: auth(["invoices:send"])
    }.to have_enqueued_job(Invoice::DeliveryJob)
    expect(response).to have_http_status(:success)
    expect(json.dig("invoice", "status")).to eq("sent")
    expect(quote.reload.status).to eq("invoiced")
  end

  it "refuses to send an invoice with nobody to send it to" do
    invoice = Invoice.create!(customer_name: "Walk-in", line_items: [{"description" => "x", "unit_price_cents" => 100}])

    post "/api/invoices/#{invoice.id}/send", headers: auth
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "deletes drafts only" do
    invoice = Invoice.from_quote_request(quote).tap(&:save!)
    invoice.send!(base_url: "https://x.test")

    delete "/api/invoices/#{invoice.id}", headers: auth
    expect(response).to have_http_status(:unprocessable_entity)

    post "/api/invoices/#{invoice.id}/void", headers: auth
    expect(json.dig("invoice", "status")).to eq("void")
  end

  it "lists and filters" do
    Invoice.from_quote_request(quote).tap(&:save!)

    get "/api/invoices?status=draft", headers: auth(["invoices:read"])
    expect(json["total"]).to eq(1)
    expect(json["invoices"].first["total"]).to eq("$2,200.00")
  end

  describe "the hosted customer page" do
    it "renders by token without a sign-in and hides everything else" do
      invoice = Invoice.from_quote_request(quote)
      invoice.payment_link = "https://buy.stripe.test/abc"
      invoice.save!
      Setting.set("commerce", {"business_name" => "Discount Bakery Equipment"})

      get "/i/#{invoice.token}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(invoice.number, "Discount Bakery Equipment", "Hobart A200", "$2,200.00",
        "https://buy.stripe.test/abc")
      expect(response.body).to include('name="robots" content="noindex')
    end

    it "404s an unknown token" do
      get "/i/not-a-real-token"
      expect(response).to have_http_status(:not_found)
    end
  end
end
