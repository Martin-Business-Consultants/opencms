# frozen_string_literal: true

require "rails_helper"

# The admin side of commerce: the pages render, the capability gates hold, and
# the state-changing buttons do what the API does.
RSpec.describe "Commerce admin", type: :request do
  let(:admin) { create(:user) }

  before { Cms::Plugins.switch!(:commerce, on: true) }
  let!(:quote) do
    QuoteRequest.create!(customer_name: "Jane Baker", customer_email: "jane@bakery.test",
      items: [{"title" => "Hobart A200", "unit_price" => "$2,200.00", "quantity" => 1}])
  end

  context "as an admin" do
    before { sign_in_as admin }

    it "renders the inbox, a request, the invoice list and a prefilled draft" do
      get "/quotes"
      expect(response).to have_http_status(:success)

      get "/quotes/#{quote.id}"
      expect(response).to have_http_status(:success)

      get "/invoices"
      expect(response).to have_http_status(:success)

      get "/invoices/new", params: {quote_request_id: quote.id}
      expect(response).to have_http_status(:success)

      get "/settings/commerce"
      expect(response).to have_http_status(:success)
    end

    it "works a quote, drafts and sends an invoice" do
      patch "/quotes/#{quote.id}", params: {quote: {status: "quoted", notes: "called"}}
      expect(response).to redirect_to("/quotes/#{quote.id}")
      expect(quote.reload.status).to eq("quoted")

      # The form's shape: lines keyed by row, amounts as people type them.
      post "/invoices", params: {invoice: {quote_request_id: quote.id, customer_name: "Jane Baker",
        customer_email: "jane@bakery.test", payment_link: "https://buy.stripe.test/x", tax: "$12.50", lines_sent: "1",
        line_items: {"n1" => {description: "Hobart A200", quantity: 1, unit_price: "$2,200.00"}}}}
      invoice = Invoice.last
      expect(response).to redirect_to("/invoices/#{invoice.id}")
      expect(invoice).to have_attributes(subtotal_cents: 220_000, tax_cents: 1250, total_cents: 221_250)

      expect { post "/invoices/#{invoice.id}/delivery" }.to have_enqueued_job(Invoice::DeliveryJob)
      expect(invoice.reload).to be_sent

      post "/invoices/#{invoice.id}/payment"
      expect(invoice.reload).to be_paid
      expect(quote.reload.status).to eq("won")
    end

    it "saves commerce settings, normalising the prefix" do
      patch "/settings/commerce", params: {settings: {notification_recipients: "sales@dbe.test", invoice_prefix: "dbe-", currency: "usd"}}
      expect(response).to redirect_to("/settings/commerce")
      expect(Setting.get("commerce")).to include("invoice_prefix" => "DBE", "currency" => "USD")
      expect(Invoice.next_number).to eq("DBE-0001")
    end
  end

  context "as a reader" do
    before { sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[quotes:read invoices:read])) }

    it "sees but cannot change" do
      get "/quotes/#{quote.id}"
      expect(response).to have_http_status(:success)

      patch "/quotes/#{quote.id}", params: {quote: {status: "lost"}}
      expect(response).to have_http_status(:redirect)
      expect(quote.reload.status).to eq("new")

      get "/invoices/new"
      expect(response).to have_http_status(:redirect)
    end
  end
end
