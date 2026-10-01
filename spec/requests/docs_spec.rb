# frozen_string_literal: true

require "rails_helper"

# Docs: the guides (app/guides), written for this install, and the go-live
# checklist, checked against the site — in the admin, the API and the CLI.
RSpec.describe "Docs", type: :request do
  let(:admin) { create(:user) }

  def api_headers = {"Authorization" => "Bearer #{admin.api_token.token}"}

  it "lists the guides and shows one, filled in for this CMS" do
    sign_in_as admin

    get docs_path
    expect(response.body).to include("How this CMS works", "Working with an Astro site", "Working with AI", "Before going live")

    get doc_path("astro")
    expect(CGI.unescapeHTML(response.body)).to include("curl -fsSL http://www.example.com/frontend/install.sh | sh", "<code>cms docs astro</code>")
    expect(response.body).not_to include("{{cms_url}}")

    get doc_path("nope")
    expect(response).to have_http_status(:not_found)
  end

  it "checks the site before it goes live, and passes a check once it's fixed" do
    sign_in_as admin

    get go_live_docs_path
    expect(CGI.unescapeHTML(response.body)).to include("The site's address is set", "Fix it", "cms go-live")

    Setting.set("general", site_base_url: "https://acme.test")
    check = GoLiveChecklist.checks.find { it.key == "site_base_url" }
    expect(check.ok).to be(true)
  end

  it "serves the guides and the checklist to the CLI and MCP" do
    get "/api/docs", headers: api_headers
    expect(response.parsed_body["guides"].map { it["slug"] }).to eq(%w[how-it-works astro ai])

    get "/api/docs/ai", headers: api_headers
    expect(response.parsed_body.dig("guide", "markdown")).to include("claude mcp add cms -- cms mcp")

    get "/api/go_live", headers: api_headers
    body = response.parsed_body
    expect(body["checks"].map { it["key"] }).to include("site_base_url", "frontend_connected", "backup")
    expect(body["summary"]).to include("total", "passing", "ready")
  end

  it "shows site health in Docs, the API and the CLI" do
    sign_in_as admin

    get site_health_docs_path
    expect(CGI.unescapeHTML(response.body)).to include("Site health", "One phone number, everywhere", "Forms are protected from spam", "cms site-health")

    get "/api/site_health", headers: api_headers
    expect(response.parsed_body["checks"].map { it["key"] }).to include("phone_consistent", "captcha", "privacy_page", "recent_backup")
  end
end
