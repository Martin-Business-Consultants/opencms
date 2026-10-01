# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Sitemap", type: :request do
  let(:user) { create(:user) }

  def auth_headers
    {"Authorization" => "Bearer #{user.api_token.token}"}
  end

  def make_page(attrs = {})
    Page.create!({
      slug:        "p-#{SecureRandom.hex(3)}",
      title:       "A page",
      status:      "published",
      locale:      "en",
      blocks:      [],
      schema:      {"fields" => []},
      frontmatter: {},
      seo:         {}
    }.merge(attrs))
  end

  describe "GET /api/sitemap" do
    it "401s without a token" do
      get "/api/sitemap"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the JSON payload with absolute URLs when configured" do
      Setting.set("general", site_base_url: "https://www.example.org")
      make_page(slug: "about")
      make_page(slug: "drafty", status: "draft")

      get "/api/sitemap", headers: auth_headers
      expect(response).to have_http_status(:success)

      body = JSON.parse(response.body)
      expect(body["site_base_url"]).to eq("https://www.example.org")
      expect(body["count"]).to eq(1)
      expect(body["entries"].first["url"]).to eq("https://www.example.org/about")
      expect(body["entries"].first["loc"]).to eq("/about")
    end
  end
end
