# frozen_string_literal: true

require "rails_helper"
require "openssl"

# The CMS half of the Lumin seam contract.
#
# The counterpart lives at ../ads/test/integration/cms_contract_test.rb and both
# assert against the same committed fixture. That arrangement exists because the
# seam had already broken in both directions without a single test noticing: the
# content webhook had never carried the URL its consumer joins on, and Lumin was
# still POSTing to /ai_proposals long after this app dropped it.
#
# If you change a payload shape here, the fixture and the Lumin test change with
# it — that is the point, not an inconvenience.
RSpec.describe "Lumin contract", type: :request do
  CONTRACT = JSON.parse(
    File.read(Rails.root.join("spec/fixtures/contracts/cms_contract.json"))
  ).freeze
  SIBLING_ADS = Rails.root.join("..", "ads")

  def json = JSON.parse(response.body)

  def auth_headers(capabilities)
    actor = create(:user, admin: false, role: create(:role, permissions: capabilities))
    {"Authorization" => "Bearer #{actor.api_token.token}"}
  end

  # --- The fixture is shared, not ours alone --------------------------------

  it "keeps the contract fixture byte-identical to Lumin's copy" do
    mirror = SIBLING_ADS.join("test/fixtures/files/cms_contract.json")
    skip "Lumin repo not checked out beside this one" unless File.exist?(mirror)

    expect(File.read(Rails.root.join("spec/fixtures/contracts/cms_contract.json")))
      .to eq(File.read(mirror)),
        "The two copies of the contract have drifted. Edit both, or neither."
  end

  # --- CMS -> Lumin: what we publish ----------------------------------------

  describe "content webhook payloads" do
    let(:page) {
      Page.create!(title: "About us", slug: "about", status: "published", locale: "en",
        blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {})
    }

    before { Setting.set("general", {"site_base_url" => "https://acme.test"}) }

    it "publishes exactly the documented keys for a page" do
      expect(page.webhook_payload.keys.map(&:to_s).sort)
        .to eq(CONTRACT.dig("webhook", "page_data_keys").sort)
    end

    it "publishes exactly the documented keys for an entry" do
      collection = Collection.create!(name: "Posts", slug: "posts", schema: {"fields" => []})
      entry = collection.entries.create!(title: "Hello", slug: "hello", status: "published",
        locale: "en", blocks: [], frontmatter: {}, seo: {})

      expect(entry.webhook_payload.keys.map(&:to_s).sort)
        .to eq(CONTRACT.dig("webhook", "entry_data_keys").sort)
    end

    # The reason the whole contract exists: Lumin joins Search Console rows to
    # CMS records by URL. A payload without one describes a page it can never
    # identify, which is what it did for the life of this webhook.
    it "carries an absolute url" do
      expect(page.webhook_payload[:url]).to eq("https://acme.test/about")
    end

    it "publishes the same address the sitemap does" do
      page_id = page.id # force it into existence before the sitemap is built
      sitemap_entry = Sitemap.new.entries.find { |e| e.id == page_id && e.source == "page" }

      expect(sitemap_entry).to be_present
      expect(page.public_path).to eq(sitemap_entry.loc)
    end

    it "honours an SEO canonical, as the sitemap does" do
      page.update!(seo: {"canonical" => "/about-us"})

      expect(page.webhook_payload[:url]).to eq("https://acme.test/about-us")
    end

    it "honours the canonical_url key the admin SEO panel saves" do
      page.update!(seo: {"canonical_url" => "/about-us"})

      expect(page.public_url).to eq("https://acme.test/about-us")
      expect(page.webhook_payload[:url]).to eq("https://acme.test/about-us")
    end

    it "falls back to a relative url rather than inventing an origin" do
      Setting.set("general", {"site_base_url" => ""})

      expect(page.webhook_payload[:url]).to eq("/about")
    end

    it "emits the documented event vocabulary" do
      expect(Webhook.events.sort).to eq(CONTRACT.dig("webhook", "events").sort)
    end
  end

  describe "the delivery envelope" do
    let(:webhook) {
      Webhook.create!(name: "lumin", url: "https://acme.golumin.test/webhooks/content",
        events: ["page.published"], secret: "site-webhook-secret")
    }

    it "wraps the payload in the documented envelope and signs the raw body" do
      captured = nil
      allow_any_instance_of(Net::HTTP).to receive(:request) do |_self, req|
        captured = req
        Class.new(Net::HTTPSuccess).new("1.1", "200", "OK").tap do |r|
          def r.body = "ok"
          def r.code = "200"
        end
      end

      DeliverWebhookJob.perform_now(webhook.id, "page.published", {slug: "about"})

      envelope = JSON.parse(captured.body)
      expect(envelope.keys.sort).to eq(CONTRACT.dig("webhook", "envelope_keys").sort)
      expect(envelope["tenant"]).to eq(Site.key)

      header = CONTRACT.dig("webhook", "signature_header")
      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", webhook.secret, captured.body)
      expect(captured[header]).to eq(expected)
    end
  end

  # --- Lumin -> CMS: what we accept -----------------------------------------

  describe "POST /api/recommendations" do
    let(:writer) { auth_headers(["recommendations:read", "recommendations:write"]) }

    it "accepts exactly the kinds Lumin is told it may send" do
      expect(Recommendation::KINDS.sort).to eq(CONTRACT.dig("recommendations", "kinds").sort)
    end

    it "accepts the documented example request" do
      Page.create!(title: "About", slug: "about", status: "published", locale: "en",
        blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {})

      post CONTRACT.dig("recommendations", "path"),
        params: CONTRACT.dig("recommendations", "example_request"),
        headers: writer

      expect(response).to have_http_status(CONTRACT.dig("recommendations", "response_status"))
      expect(json.keys).to eq(CONTRACT.dig("recommendations", "response_keys"))
      expect(json["recommendation"].keys.sort)
        .to eq(CONTRACT.dig("recommendations", "response_recommendation_keys").sort)
      expect(json.dig("recommendation", "subject", "type")).to eq("Page")
    end

    # Lumin sends paths without a leading slash because Page#path has none.
    it "resolves a subject path spelled the way the contract spells it" do
      page = Page.create!(title: "About", slug: "about", status: "published", locale: "en",
        blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {})

      expect(page.path).to eq(CONTRACT.dig("recommendations", "subject_forms").first["path"])
    end

    # The finding Lumin most needs to file names no record at all.
    it "files a finding with no subject rather than rejecting it" do
      post CONTRACT.dig("recommendations", "path"), params: {
        recommendation: {kind: "content_gap", title: "No page for 'emergency plumber'", impact: 4}
      }, headers: writer

      expect(response).to have_http_status(:created)
      expect(json.dig("recommendation", "subject")).to be_nil
    end

    it "keeps every Lumin kind mappable" do
      mapped = CONTRACT.dig("recommendations", "lumin_kind_map").values.uniq

      expect(mapped - Recommendation::KINDS).to be_empty,
        "Lumin maps its findings onto kinds this app no longer accepts"
    end
  end
end
