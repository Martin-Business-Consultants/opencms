# frozen_string_literal: true

require "rails_helper"

# Consent management: the settings a person edits, the scripts filed under
# categories, and the public embed that puts the two in front of a visitor.
RSpec.describe "Consent management", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in_as user
    Script.delete_all
    Setting.delete_key("consent")
  end

  describe "the public embed" do
    it "is a no-op comment while the banner is off" do
      get "/consent.js"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      expect(response.body).to start_with("/* Consent management is switched off")
      expect(response.body).not_to include("__LUMIN_CONSENT__")
    end

    it "carries the config and only the active scripts, with the payload escaped for a script tag" do
      Consent::Config.save("enabled" => "1", "mode" => "opt_out")
      Script.create!(name: "GA", category: "analytics", src: "https://www.googletagmanager.com/gtag/js?id=G-1", code: "gtag('config','G-1')")
      Script.create!(name: "Old pixel", category: "marketing", code: "fbq()", active: false)
      Script.create!(name: "Sneaky", category: "necessary", code: "var s = '</script><script>alert(1)</script>'")

      get "/consent.js", headers: {"Origin" => "https://www.example.com"}

      expect(response).to have_http_status(:ok)
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
      expect(response.headers["Cache-Control"]).to include("public")
      json = response.body[/window\.__LUMIN_CONSENT__ = (.*?);\n/m, 1]
      expect(json).not_to include("</script>")
      payload = JSON.parse(json)
      expect(payload["config"]["enabled"]).to be(true)
      expect(payload["config"]["mode"]).to eq("opt_out")
      expect(payload["scripts"].map { |s| s["name"] }).to contain_exactly("GA", "Sneaky")
      expect(payload["scripts"].first.keys).to contain_exactly("id", "name", "category", "placement", "src", "code", "async", "defer")
      # The runtime follows the payload.
      expect(response.body).to include("window.luminConsent")
    end

    it "serves the same payload as JSON without a session" do
      sign_out
      Consent::Config.save("enabled" => true)

      get "/consent.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["config"]["banner"]["title"]).to eq("We use cookies")
    end
  end

  describe "the build-facing API" do
    let(:site) { create(:user, admin: false, role: create(:role, permissions: Permissions.defaults_for(:site))) }
    let(:headers) { {"Authorization" => "Bearer #{site.api_token.token}"} }

    it "gives a site token the consent payload and the script list" do
      sign_out
      Script.create!(name: "GA", category: "analytics", code: "1")
      Script.create!(name: "Off", category: "marketing", code: "1", active: false)

      get "/api/consent", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["scripts"].map { |s| s["name"] }).to eq(["GA"])

      get "/api/scripts", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["scripts"].map { |s| [s["name"], s["active"]] }).to eq([["GA", true], ["Off", false]])
    end
  end

  describe "Settings → Consent" do
    it "shows defaults before anything is saved, with the script counts" do
      Script.create!(name: "GA", category: "analytics", code: "1")

      get "/settings/consent"

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[type=checkbox][name='consent[enabled]']")["checked"]).to be_nil
      expect(page.at_css("input[type=checkbox][name='consent[categories][analytics][enabled]']")["checked"]).to eq("checked")
      expect(response.body).to include("Banner is off", "Off, no scripts are served", "· 1 script", "/consent.js")
      expect(page.at_css("input[name='consent[version]']")["value"]).to eq("1")
    end

    it "normalizes what the form sends and drops what it doesn't know" do
      patch "/settings/consent", params: {consent: {
        enabled: "true", mode: "sideways", position: "center", expiry_days: "9000", version: "0",
        banner: {title: "  Cookies?  ", policy_url: "https://x.test/privacy", accept_label: ""},
        categories: {marketing: {enabled: "false", label: "Ads"}, bogus: {enabled: true}},
        evil: "1"
      }}

      expect(response).to redirect_to("/settings/consent")
      saved = Consent::Config.load.to_h
      expect(saved["enabled"]).to be(true)
      expect(saved["mode"]).to eq("opt_in")
      expect(saved["position"]).to eq("center")
      expect(saved["expiry_days"]).to eq(730)
      expect(saved["version"]).to eq(1)
      expect(saved["banner"]["title"]).to eq("Cookies?")
      expect(saved["banner"]["accept_label"]).to eq("Accept all")
      expect(saved["banner"]["policy_url"]).to eq("https://x.test/privacy")
      expect(saved["categories"]["marketing"]).to eq("enabled" => false, "label" => "Ads", "description" => Consent::Config::DEFAULTS["categories"]["marketing"]["description"])
      expect(saved["categories"].keys).to eq(%w[functional analytics marketing])
      expect(saved).not_to have_key("evil")
      expect(Consent::Config.load.enabled_categories).to eq(%w[functional analytics])
    end

    it "bumps the version to ask everyone again" do
      Consent::Config.save("enabled" => true)
      post "/settings/consent/reconsent"
      expect(Consent::Config.load.version).to eq(2)
    end
  end

  describe "Tools → Scripts" do
    it "lists scripts with the presets and the banner's state" do
      switch_plugin(:local_marketing, on: true)
      Script.create!(name: "GA", category: "analytics", code: "1")

      get "/scripts"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("GA", "Google Analytics 4", "Meta Pixel", "Consent banner is off", "Not checked")
      expect(response.body).to include("New script", "Check the site")

      ga = Script.find_by!(name: "GA")
      Report.create!(kind: "site_audit", status: "complete", completed_at: Time.current,
                     data: {"tracking" => {"managed" => [{"id" => ga.id, "status" => "not_served", "status_label" => "Not on the site"}]}, "findings" => [], "passed" => [], "counts" => {}})
      get "/scripts"
      expect(response.body).to include("Not on the site", "1 active script not on the site")
      Report.delete_all
    end

    it "creates, toggles and removes a script, and reports validation errors" do
      post "/scripts", params: {script: {name: "Pixel", vendor: "Meta", category: "marketing", placement: "head", code: "fbq('init','1')", async: true, defer: false, active: true}}
      expect(response).to redirect_to("/scripts")
      script = Script.find_by!(name: "Pixel")
      expect(script.category).to eq("marketing")

      patch "/scripts/#{script.id}", params: {script: {active: false}}
      expect(script.reload.active).to be(false)

      post "/scripts", params: {script: {name: "Broken", category: "analytics"}}
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/URL, inline code/)

      delete "/scripts/#{script.id}"
      expect(Script.exists?(script.id)).to be(false)
      expect(AuditLog.where(action: %w[script.created script.updated script.deleted]).count).to eq(3)
    end

    it "fills a preset's snippet from the ID" do
      get "/scripts/new", params: {preset: "ga4"}
      expect(response.body).to include("Measurement ID")

      post "/scripts", params: {preset: "ga4", preset_id: "G-ABC123", script: {name: "GA4", category: "analytics", placement: "head", active: true}}
      expect(response).to redirect_to("/scripts")
      expect(Script.find_by!(name: "GA4").src).to eq("https://www.googletagmanager.com/gtag/js?id=G-ABC123")

      post "/scripts", params: {preset: "ga4", preset_id: "G-1'); alert(1", script: {name: "Bad", category: "analytics", placement: "head"}}
      expect(response).to have_http_status(:unprocessable_content)
      expect(Script.exists?(name: "Bad")).to be(false)
    end
  end

  context "as an editor" do
    let(:user) { create(:user, admin: false, role: create(:role, permissions: Permissions.defaults_for(:editor))) }

    it "can read scripts and the consent settings but change neither" do
      get "/scripts"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("New script", "Check the site")

      get "/settings/consent"
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("fieldset.settings-fieldset")["disabled"]).to be_present
      expect(response.body).not_to include("Ask everyone again")

      # Browser requests are turned back to where they came from, not 403'd.
      post "/scripts", params: {script: {name: "Pixel", category: "marketing", code: "1"}}
      expect(response).to have_http_status(:redirect)
      expect(Script.count).to eq(0)

      patch "/settings/consent", params: {consent: {enabled: true}}
      expect(response).to have_http_status(:redirect)
      expect(Consent::Config.load.enabled?).to be(false)
    end
  end
end
