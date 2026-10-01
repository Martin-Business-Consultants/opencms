# frozen_string_literal: true

require "rails_helper"

# The public "request a quote" endpoint a product page posts to, and the
# authenticated inbox behind `cms quotes`.
RSpec.describe "Api quote requests", type: :request do
  let(:admin) { create(:user) }

  before { Cms::Plugins.switch!(:commerce, on: true) }

  def auth(capabilities = nil)
    actor = capabilities ? create(:user, admin: false, role: create(:role, permissions: capabilities)) : admin
    {"Authorization" => "Bearer #{actor.api_token.token}"}
  end

  def json = JSON.parse(response.body)

  let(:payload) do
    {
      customer_name: "Jane Baker", customer_email: "Jane@Bakery.test", customer_phone: "555-0100",
      company: "Jane's Bakery", message: "Need freight to Ohio", page_url: "https://shop.test/product/a200",
      items: [{title: "Hobart A200 20Qt Mixer", slug: "a200", sku: "A200", url: "https://shop.test/product/a200",
               unit_price: "$2,200.00", quantity: 2}]
    }
  end

  describe "POST /api/quote_requests (public)" do
    before { Setting.set("general", {"site_base_url" => "https://shop.test", "public_origins" => ["https://preview.shop.test"]}) }

    it "stores the request with the items as the visitor saw them and answers CORS for the site" do
      expect {
        post "/api/quote_requests", params: payload, as: :json, headers: {"Origin" => "https://shop.test"}
      }.to change(QuoteRequest, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["ok"]).to eq(true)
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://shop.test")

      quote = QuoteRequest.last
      expect(quote.customer_email).to eq("jane@bakery.test")
      expect(quote.source).to eq("site")
      expect(quote.items.first).to include("title" => "Hobart A200 20Qt Mixer", "unit_price" => "$2,200.00", "quantity" => 2)
      expect(quote.summary).to eq("Hobart A200 20Qt Mixer")
    end

    it "emits the webhook event and queues the shop's notification" do
      Setting.set("commerce", {"notification_recipients" => "sales@shop.test"})

      expect {
        post "/api/quote_requests", params: payload, as: :json
      }.to have_enqueued_job(QuoteRequest::NotificationJob)
    end

    it "requires a name and a way to reach the customer" do
      post "/api/quote_requests", params: {customer_name: "", message: "hi"}, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"].keys).to include("customer_name", "base")
    end

    it "drops honeypot fills silently" do
      expect {
        post "/api/quote_requests", params: payload.merge(website: "http://spam.test"), as: :json
      }.not_to change(QuoteRequest, :count)
      expect(response).to have_http_status(:created)
    end

    it "does not grant CORS to an unknown origin" do
      post "/api/quote_requests", params: payload, as: :json, headers: {"Origin" => "https://evil.test"}
      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end

    it "needs no token" do
      post "/api/quote_requests", params: payload, as: :json
      expect(response).to have_http_status(:created)
    end
  end

  describe "the inbox" do
    let!(:quote) do
      QuoteRequest.create!(customer_name: "Jane", customer_email: "jane@bakery.test",
        items: [{"title" => "Mixer", "unit_price" => "$10.00", "quantity" => 1}])
    end

    it "lists with counts for quotes:read" do
      get "/api/quotes", headers: auth(["quotes:read"])

      expect(response).to have_http_status(:success)
      expect(json["total"]).to eq(1)
      expect(json["counts"]).to eq("new" => 1)
      expect(json["quotes"].first).to include("id" => quote.id, "summary" => "Mixer", "item_count" => 1)
    end

    it "is gated" do
      get "/api/quotes", headers: auth(["pages:read"])
      expect(response).to have_http_status(:forbidden)
    end

    it "moves a request along the ladder with quotes:write" do
      patch "/api/quotes/#{quote.id}", params: {quote: {status: "quoted", notes: "called back"}}, as: :json,
        headers: auth(["quotes:read", "quotes:write"])

      expect(response).to have_http_status(:success)
      expect(quote.reload.status).to eq("quoted")
      expect(quote.notes).to eq("called back")
    end

    it "rejects an unknown status" do
      patch "/api/quotes/#{quote.id}", params: {quote: {status: "maybe"}}, as: :json, headers: auth
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "lets staff file a request by hand" do
      post "/api/quotes", params: {quote: {customer_name: "Phone lead", customer_phone: "555", message: "wants an oven"}},
        as: :json, headers: auth(["quotes:write"])

      expect(response).to have_http_status(:created)
      expect(json.dig("quote", "source")).to eq("api")
    end

    it "wraps the inbox in the agent envelope with a next step" do
      get "/api/quotes", headers: auth.merge("X-Agent-Envelope" => "1")

      expect(json["summary"]).to eq("1 quote request, 1 new.")
      expect(json["breadcrumbs"].map { |c| c["command"] }).to include("cms quote #{quote.id}")
    end
  end
end
