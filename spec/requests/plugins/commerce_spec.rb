# frozen_string_literal: true

require "rails_helper"

# The Commerce plugin (engines/commerce): the admin screens, where it sits
# among the core's things, and what disappears when it's off. The API is
# covered by spec/requests/api/{quote_requests,invoices}_spec.rb, the flow by
# spec/requests/commerce_spec.rb.
RSpec.describe "The Commerce plugin", type: :request do
  let(:admin) { create(:user) }

  def api_headers(user = admin) = {"Authorization" => "Bearer #{user.api_token.token}"}

  def make_quote(**attrs)
    QuoteRequest.create!({customer_name: "Jane Baker", customer_email: "jane@bakery.test",
                          items: [{"title" => "Hobart A200", "unit_price" => "$2,200.00", "quantity" => 1}]}.merge(attrs))
  end

  describe "switched on" do
    before do
      switch_plugin :commerce, on: true
      sign_in_as admin
    end

    it "lists quote requests and invoices in the Hotwire layout, filtered by status" do
      quote = make_quote
      make_quote(customer_name: "Lost Cause", status: "lost")
      Invoice.from_quote_request(quote).tap(&:save!)

      get quote_requests_path, params: {status: "new"}
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Jane Baker", "Hobart A200")
      expect(response.body).not_to include("Lost Cause")

      get invoices_path
      expect(response.body).to include("INV-0001", "$2,200.00")
    end

    it "shows a visitor's page and item links as text unless they're http(s)" do
      quote = make_quote(page_url: "javascript:alert(1)",
        items: [{"title" => "Mixer", "url" => "javascript:alert(2)"}, {"title" => "Oven", "url" => "https://shop.test/oven"}])

      get quote_request_path(quote)

      expect(response.body).not_to include('href="javascript:')
      expect(response.body).to include("javascript:alert(1)", 'href="https://shop.test/oven"')
    end

    it "drafts an invoice from a quote request, prefilled with its items" do
      quote = make_quote

      get new_invoice_path(quote_request_id: quote.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Drafted from quote request ##{quote.id}", 'value="Hobart A200"', 'value="$2,200.00"')
    end

    it "re-renders the form with what was typed when a save fails" do
      post invoices_path, params: {invoice: {customer_name: "", payment_link: "not a link", lines_sent: "1",
                                             line_items: {"n1" => {description: "Mixer", quantity: 2, unit_price: "$10"}}}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That didn’t work", 'value="Mixer"', 'value="$10.00"')
    end

    it "saves an edit that removes every line" do
      invoice = Invoice.from_quote_request(make_quote).tap(&:save!)

      patch invoice_path(invoice), params: {invoice: {customer_name: "Jane Baker", lines_sent: "1"}}

      expect(invoice.reload.line_items).to eq([])
      expect(invoice.total_cents).to eq(0)
    end

    it "voids an invoice and only deletes drafts" do
      invoice = Invoice.from_quote_request(make_quote).tap(&:save!)

      post invoice_voiding_path(invoice)
      expect(invoice.reload).to be_void
      expect(AuditLog.last.action).to eq("invoice.voided")

      delete invoice_path(invoice)
      expect(Invoice.exists?(invoice.id)).to be(true)
      expect(flash[:alert]).to match(/Only drafts/)
    end

    it "deletes the ticked quote requests" do
      a = make_quote
      b = make_quote(customer_name: "Other")

      post quote_requests_bulk_deletions_path, params: {ids: [a.id, b.id]}

      expect(QuoteRequest.count).to eq(0)
      expect(flash[:notice]).to eq("2 quote requests deleted")
    end

    it "puts its Menu group after Content, and its capabilities after Forms" do
      get pages_path
      groups = menu_groups
      expect(groups.index("Content")).to be < groups.index("Commerce")
      expect(groups.index("Commerce")).to be < groups.index("Structure")
      expect(submenu_labels("Commerce")).to eq(["Quote requests", "Invoices", "Add invoice", "Settings"])

      expect(Permissions.catalog.keys.each_cons(2)).to include(%w[Forms Commerce])
      expect(Permissions.defaults_for(:editor)).to include("invoices:send")
    end

    it "offers its webhook events, and adds its manifest section after counts" do
      get new_webhook_path
      expect(response.body).to include("quote_request.created", "invoice.paid")

      get "/api/manifest", headers: api_headers
      manifest = JSON.parse(response.body)
      expect(manifest.keys.each_cons(2)).to include(%w[counts commerce])
      expect(manifest["counts"].keys.last(2)).to eq(%w[quote_requests invoices])
    end
  end

  describe "switched off" do
    let!(:quote) { make_quote }
    let!(:invoice) { Invoice.from_quote_request(quote).tap(&:save!) }

    before { switch_plugin :commerce, on: false }

    it "takes away its pages, its API, the public endpoints and the hosted invoice" do
      sign_in_as admin

      [quote_requests_path, quote_request_path(quote), invoices_path, invoice_path(invoice), new_invoice_path,
        settings_commerce_path].each do |path|
        get path
        expect(response).to have_http_status(:not_found), "#{path} returned #{response.status}"
      end

      get "/api/quotes", headers: api_headers
      expect(response).to have_http_status(:not_found)
      post "/api/invoices/#{invoice.id}/send", headers: api_headers
      expect(response).to have_http_status(:not_found)

      post "/api/quote_requests", params: {customer_name: "A", customer_email: "a@b.test"}, as: :json
      expect(response).to have_http_status(:not_found)
      expect(QuoteRequest.count).to eq(1)

      get public_invoice_path(invoice.token)
      expect(response).to have_http_status(:not_found)
    end

    it "leaves the core without it, but keeps webhooks subscribed to its events valid" do
      sign_in_as admin
      get pages_path
      expect(response.body).not_to include(">Quote requests<", ">Invoices<", ">Commerce<")

      get "/api/manifest", headers: api_headers
      manifest = JSON.parse(response.body)
      expect(manifest).not_to have_key("commerce")
      expect(manifest["counts"]).not_to have_key("invoices")
      expect(Permissions.catalog).not_to have_key("Commerce")

      webhook = Webhook.create!(name: "Paid", url: "https://hooks.example.test/in", events: %w[invoice.paid])
      expect(webhook).to be_valid
      get edit_webhook_path(webhook)
      expect(response.body).not_to include('value="quote_request.created"')
    end
  end

  it "is adopted by an install that already has quote requests or invoices" do
    expect(Cms::Plugins.enabled?(:commerce)).to be(false)

    make_quote
    Current.plugin_adoptions = nil

    expect(Cms::Plugins.enabled?(:commerce)).to be(true)
  end
end
