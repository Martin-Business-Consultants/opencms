# frozen_string_literal: true

require "rails_helper"

# The Consent & Scripts plugin (engines/consent_scripts) switched off: its
# pages, the public embed and its API go, and the core carries on without it.
# What it does while on is spec/requests/consent_spec.rb.
RSpec.describe "The Consent & Scripts plugin", type: :request do
  let(:admin) { create(:user) }

  def api_headers = {"Authorization" => "Bearer #{admin.api_token.token}"}

  before do
    Script.create!(name: "GA4", category: "analytics", placement: "head", src: "https://www.googletagmanager.com/gtag/js?id=G-1", active: true)
    Setting.set("consent", {"enabled" => true})
  end

  it "is on by default and serves the embed" do
    get "/consent.js"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("window.__LUMIN_CONSENT__")
  end

  context "switched off" do
    before { switch_plugin :consent_scripts, on: false }

    it "takes away the embed, its pages and its API" do
      get "/consent.js"
      expect(response).to have_http_status(:not_found)
      get "/consent.json"
      expect(response).to have_http_status(:not_found)

      get "/api/scripts", headers: api_headers
      expect(response).to have_http_status(:not_found)
      get "/api/consent", headers: api_headers
      expect(response).to have_http_status(:not_found)

      sign_in_as admin
      get scripts_path
      expect(response).to have_http_status(:not_found)
      get settings_consent_path
      expect(response).to have_http_status(:not_found)
    end

    it "leaves the core without it: no menu link, no settings section, no capabilities, no embed on the preview" do
      sign_in_as admin

      get settings_path
      expect(response.body).not_to include(">Consent<")
      get pages_path
      expect(response.body).not_to include(">Scripts<")

      expect(Permissions.catalog.keys).not_to include("Scripts", "Consent")
      expect(Cms::Plugins.provided(:consent_config)).to be_nil
      expect(Cms::Plugins.manifest_listing.map { it[:key] }).not_to include("consent_scripts")
    end
  end
end
