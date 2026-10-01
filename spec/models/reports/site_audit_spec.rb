# frozen_string_literal: true

require "rails_helper"

# The site audit compares the live site with what the CMS expects. These
# specs hand it rendered pages shaped like DataForSEO's answer — with our
# probe's object inside — and the plain GETs a server would make, and assert
# on the findings: the gaps it must catch, and the passes it must grant.
RSpec.describe Reports::Definitions::SiteAudit do
  before do
    Rails.cache.clear
    Script.delete_all
    FormSubmission.delete_all
    Form.with_discarded.destroy_all
    Setting.delete_key("consent")
    Setting.delete_key("site_audit")
    Setting.set("general", "site_base_url" => "https://www.acme.test", "title" => "Acme Plumbing")
  end

  # DataForSEO stands in: one instant_pages result per task, in order.
  class AuditFakeClient
    attr_reader :calls

    def initialize(items_by_url)
      @items = items_by_url
      @calls = []
    end

    # One render per call, like the definition makes them. A page whose item
    # is an exception is what DataForSEO refusing the task looks like.
    def post(path, task)
      @calls << [path, task]
      key = task[:url].include?("gclid") ? :paid : task[:url].split("?").first.chomp("/")
      item = @items.fetch(key) { @items.fetch(task[:url].split("?").first.chomp("/")) { @items[:default] } }
      raise item if item.is_a?(Exception)
      raise DataForSeo::Error.new("DataForSEO task for #{path} failed (40000): Task Timeout.", status_code: 40_000) if item.nil?

      DataForSeo::Response.new(result: [{"items" => [item.merge("url" => task[:url])]}], cost: 0.005, task_id: "x", time: "1")
    end

    def urls = @calls.map { |_, task| task[:url] }
  end

  def item(probe, status: 200, score: 90.0)
    {"status_code" => status, "onpage_score" => score, "meta" => {"title" => "Acme"}, "custom_js_response" => probe}
  end

  def probe(**over)
    {
      "scripts" => [], "inline" => [], "globals" => {}, "banner" => false, "embed" => nil, "injected" => nil,
      "phones" => [], "tel" => [], "forms" => [], "cookies" => [],
      "meta" => {"title" => "Acme", "verification" => nil, "canonical" => "https://www.acme.test/", "robots" => nil, "viewport" => "width=device-width"},
      "jsonld" => [], "iframes" => []
    }.merge(over.transform_keys(&:to_s))
  end

  def fetch(url, status: 200, body: "", headers: {})
    Reports::Audit::Fetch::Result.new(url: url, status: status, body: body, headers: headers, redirects: [])
  end

  def stub_fetches(robots: "User-agent: *\nAllow: /\nSitemap: https://www.acme.test/sitemap.xml\n",
                   sitemap: "<urlset><url><loc>https://www.acme.test/</loc></url><url><loc>https://www.acme.test/contact</loc></url></urlset>",
                   alt: fetch("https://acme.test/", status: 301, headers: {"location" => "https://www.acme.test/"}))
    allow(Reports::Audit::Fetch).to receive(:get) do |url, **|
      case url
      when %r{/robots\.txt} then robots.is_a?(String) ? fetch(url, body: robots) : robots
      when %r{/sitemap\.xml} then sitemap.is_a?(String) ? fetch(url, body: sitemap) : sitemap
      when %r{\Ahttps://acme\.test/} then alt
      else fetch(url, headers: {})
      end
    end
  end

  def run(items, profile_data = {"phone" => "(555) 123-4567", "audit_urls" => "https://www.acme.test/contact"})
    profile = Reports::Profile.new(profile_data, Setting.get("general"))
    client = AuditFakeClient.new(items)
    definition = described_class.new(profile: profile, client: client)
    [definition.call.with_indifferent_access, client]
  end

  def keys(data) = data[:findings].map { |f| f[:key] }

  it "keeps the probe under DataForSEO's limit and renders the home page twice, once as a paid click" do
    expect(Reports::Audit::Probe::SCRIPT.length).to be <= Reports::Audit::Probe::MAX_LENGTH
    stub_fetches
    _, client = run("https://www.acme.test" => item(probe), "https://www.acme.test/contact" => item(probe))

    expect(client.calls.map(&:first).uniq).to eq(["on_page/instant_pages"])
    expect(client.urls).to eq(["https://www.acme.test/", "https://www.acme.test/contact", "https://www.acme.test/?#{described_class::PAID_QUERY}"])
    expect(client.calls.map(&:last)).to all(include(enable_javascript: true, custom_js: Reports::Audit::Probe::SCRIPT))
  end

  context "a site that drifted from the CMS" do
    before do
      Consent::Config.save("enabled" => true, "mode" => "opt_in", "banner" => {"policy_url" => ""})
      Script.create!(Scripts::Presets.build("ga4", id: "G-MANAGED"))
      form = Form.create!(slug: "quote", title: "Get a quote", status: "published", fields: [
        {"name" => "name", "label" => "Name", "type" => "text", "required" => true},
        {"name" => "phone", "label" => "Phone", "type" => "tel", "required" => true},
        {"name" => "message", "label" => "Message", "type" => "textarea"}
      ])
      form.notification_email.update!(enabled: false)
      stub_fetches(robots: "User-agent: *\nDisallow: /\n", sitemap: fetch("https://www.acme.test/sitemap.xml", status: 404),
                   alt: fetch("https://acme.test/", status: 200, body: "<html>"))
    end

    let(:home) do
      probe(
        "scripts" => ["https://www.googletagmanager.com/gtag/js?id=G-HARDCODED", "https://connect.facebook.net/en_US/fbevents.js"],
        "inline" => ["fbq('init', '12345'); fbq('track', 'PageView');"],
        "globals" => {"gtag" => true, "fbq" => true, "luminConsent" => false},
        "banner" => false,
        "phones" => ["(555) 999-0000"], "tel" => [],
        "cookies" => %w[_ga _fbp session],
        "meta" => {"title" => "Acme", "verification" => nil, "canonical" => "https://staging.acme.test/", "robots" => "noindex", "viewport" => nil}
      )
    end
    let(:contact) do
      probe("forms" => [{"action" => "https://cms.acme.test/api/forms/quote/submissions", "method" => "post",
                         "fields" => [{"name" => "name", "type" => "text", "required" => true}, {"name" => "message", "type" => "textarea", "required" => false}]}])
    end

    it "files the gaps: consent missing, tags early and unmanaged, wrong phone, broken form, unindexable" do
      data, = run("https://www.acme.test" => item(home), "https://www.acme.test/contact" => item(contact))
      found = keys(data)

      expect(found).to include("consent:embed-missing")
      # With no embed there is nothing to gate, so the early-load findings
      # wait for the embed rather than piling onto the same root cause.
      expect(found).not_to include("tracking:early:ga4")
      expect(found).to include("tracking:unmanaged:meta_pixel")
      expect(found).not_to include("tracking:unmanaged:ga4") # GA4 is in Scripts, even if a copy is hard-coded
      expect(found).to include("calls:wrong-number", "calls:not-tappable")
      expect(found).to include("forms:fields:quote", "forms:notify:quote", "forms:honeypot:quote")
      expect(found).to include("search:robots-blocks", "search:sitemap-missing", "search:verification",
                               "search:noindex", "search:canonical", "search:viewport", "search:alt-host", "search:schema")

      by_key = data[:findings].index_by { |f| f[:key] }
      expect(by_key["consent:embed-missing"][:severity]).to eq("critical")
      expect(by_key["consent:embed-missing"][:fix]).to include(href: "/settings/consent")
      expect(by_key["forms:fields:quote"][:title]).to include("phone")
      expect(by_key["forms:fields:quote"][:fix][:href]).to eq("/forms/quote/edit")
      expect(by_key["calls:wrong-number"][:body]).to include("(555) 999-0000").and include("(555) 123-4567")
      expect(data[:findings].first[:severity]).to eq("critical")
      expect(data[:counts][:critical]).to be >= 3
      expect(data[:tracking][:detected].map { |v| v[:key] }).to contain_exactly("ga4", "meta_pixel")
      expect(data[:tracking][:detected].find { |v| v[:key] == "meta_pixel" }[:ids]).to eq(["12345"])
      expect(data[:narrative]).to be_nil # no Zen key in test
    end

    it "without the Consent & Scripts or Forms plugins, still audits the rest and names nothing they'd manage" do
      switch_plugin :consent_scripts, on: false
      switch_plugin :forms, on: false

      data, = run("https://www.acme.test" => item(home), "https://www.acme.test/contact" => item(contact))
      found = keys(data)

      expect(found.grep(/\Aconsent:/)).to be_empty
      expect(found.grep(/\Aforms:(fields|notify|honeypot):/)).to be_empty
      expect(found).to include("tracking:unmanaged:meta_pixel", "tracking:unmanaged:ga4", "calls:wrong-number", "search:noindex")
      expect(data[:tracking][:managed]).to eq([])
    end

    it "once the embed is live, reports what still runs ahead of consent" do
      # The embed is live but was handed an empty script list — a stale
      # cached /consent.js, or one from another CMS.
      home_with_embed = home.merge("banner" => true, "globals" => home["globals"].merge("luminConsent" => true),
                                   "embed" => {"v" => 1, "ids" => []}, "injected" => [])
      data, = run("https://www.acme.test" => item(home_with_embed), "https://www.acme.test/contact" => item(contact))

      expect(keys(data)).to include("tracking:early:ga4", "tracking:early:meta_pixel", "tracking:cookies", "consent:policy")
      early = data[:findings].find { |f| f[:key] == "tracking:early:ga4" }
      expect(early[:body]).to include("hard-coded")
      expect(data[:passed].map { |p| p[:key] }).to include("consent:embed")

      ga = Script.find_by!(name: "Google Analytics 4")
      row = data[:tracking][:managed].find { |m| m[:id] == ga.id }
      # A copy of GA4 is hard-coded on the page, so it IS on the site — just not through Scripts.
      expect(row).to include(served: false, injected: false, detected: true, status: "hardcoded")
    end
  end

  context "a site that matches the CMS" do
    before do
      Consent::Config.save("enabled" => true, "mode" => "opt_in", "banner" => {"policy_url" => "https://www.acme.test/privacy"})
      Script.create!(Scripts::Presets.build("ga4", id: "G-OK"))
      Script.create!(name: "Turnstile", category: "necessary", src: "https://challenges.cloudflare.com/turnstile/v0/api.js")
      # Call tracking filed as necessary: the operator wants it before consent.
      Script.create!(name: "CallRail", category: "necessary", src: "https://cdn.callrail.com/companies/1/2/12/swap.js")
      Form.create!(slug: "contact", title: "Contact", status: "published", created_at: 60.days.ago, fields: [
        {"name" => "name", "label" => "Name", "type" => "text", "required" => true},
        {"name" => "email", "label" => "Email", "type" => "email", "required" => true}
      ]).notification_email.update!(enabled: true, recipients: "owner@acme.test", subject: "New", body: "x")
      stub_fetches
    end

    let(:ids) { Script.active.pluck(:id) }
    let(:home) do
      probe(
        "scripts" => ["https://challenges.cloudflare.com/turnstile/v0/api.js", "https://cdn.callrail.com/companies/1/2/12/swap.js"],
        "globals" => {"luminConsent" => true, "CallTrk" => true}, "banner" => true,
        "embed" => {"v" => 1, "ids" => ids}, "injected" => ids,
        "phones" => ["(555) 123-4567"], "tel" => ["tel:+15551234567"],
        "meta" => {"title" => "Acme", "verification" => "abc", "canonical" => "https://www.acme.test/", "robots" => nil, "viewport" => "width=device-width"},
        "jsonld" => %w[Plumber WebSite],
        "forms" => [{"action" => "https://cms.acme.test/api/forms/contact/submissions", "method" => "post",
                     "fields" => [{"name" => "name", "type" => "text", "required" => true}, {"name" => "email", "type" => "email", "required" => true}, {"name" => "_hp", "type" => "text", "required" => false}]}]
      )
    end
    let(:paid) { home.merge("phones" => ["(555) 800-0001"], "tel" => ["tel:+15558000001"]) }

    it "grants the passes, sees the number swap for a paid click, and raises nothing above low" do
      # The paid render is the same URL with a query; it gets the swapped page.
      items = {"https://www.acme.test" => item(home), "https://www.acme.test/contact" => item(home), paid: item(paid)}
      data, = run(items, {"phone" => "555-123-4567", "audit_urls" => "https://www.acme.test/contact"})

      passed = data[:passed].map { |p| p[:key] }
      expect(passed).to include("consent:embed", "consent:gated", "consent:cookies", "tracking:managed",
                                "calls:present", "calls:tappable", "calls:dni", "forms:ok:contact",
                                "search:robots", "search:sitemap", "search:verification", "search:canonical", "search:alt-host", "search:schema", "pages:home")
      expect(data[:findings].map { |f| f[:severity] }.uniq - %w[low]).to eq([]), data[:findings].map { |f| f[:key] }.inspect
      expect(data[:phones]).to include(swap_observed: true, business: "(555) 123-4567", vendors: ["callrail"])
      expect(data[:phones][:paid]).to eq(["(555) 800-0001"])
      expect(data[:forms].first).to include(healthy: true, honeypot: true, posts_to_cms: true)
      expect(data[:tracking][:managed].map { |m| m[:status] }.uniq).to eq(["on_site"])
      expect(passed.grep(/tracking:script:/).length).to eq(3)
      expect(data[:tracking][:embed]).to include(version: 1)
      expect(described_class.trend_point(data.deep_stringify_keys)).to include("critical" => 0, "passed" => data[:passed].length)
    end

    it "says which scripts the site was never handed, and which its consent settings block" do
      Script.create!(name: "Pixel", category: "marketing", code: "fbq('init','1')")
      Consent::Config.save("enabled" => true, "mode" => "opt_in", "categories" => {"marketing" => {"enabled" => false}})
      served = Script.where.not(name: "Pixel").pluck(:id)
      home2 = home.merge("embed" => {"v" => 2, "ids" => served - [Script.find_by!(name: "Turnstile").id]}, "injected" => served - [Script.find_by!(name: "Turnstile").id])
      data, = run({"https://www.acme.test" => item(home2), "https://www.acme.test/contact" => item(home2), paid: item(paid)}, {"phone" => "555-123-4567"})

      by_id = data[:tracking][:managed].index_by { |m| m[:name] }
      expect(by_id["Pixel"][:status]).to eq("category_off")
      expect(by_id["Turnstile"][:status]).to eq("hardcoded") # its loader is on the page even though the embed didn't serve it
      expect(by_id["Google Analytics 4"][:status]).to eq("on_site")
      expect(keys(data)).to include("tracking:script:#{Script.find_by!(name: "Pixel").id}")
      pixel = data[:findings].find { |f| f[:key] == "tracking:script:#{Script.find_by!(name: "Pixel").id}" }
      expect(pixel[:title]).to include("switched off in the consent settings")

      home3 = home.merge("embed" => {"v" => 1, "ids" => []}, "injected" => [], "scripts" => [])
      data, = run({"https://www.acme.test" => item(home3), "https://www.acme.test/contact" => item(home3), paid: item(home3)}, {"phone" => "555-123-4567"})
      ga = Script.find_by!(name: "Google Analytics 4")
      expect(data[:tracking][:managed].find { |m| m[:id] == ga.id }[:status]).to eq("not_served")
      expect(data[:findings].find { |f| f[:key] == "tracking:script:#{ga.id}" }).to include(severity: "high", title: "Google Analytics 4 isn't on the site")
    end

    it "notices call tracking that never swaps" do
      items = {"https://www.acme.test" => item(home), "https://www.acme.test/contact" => item(home), default: item(home)}
      data, = run(items, {"phone" => "555-123-4567"})
      expect(keys(data)).to include("calls:dni-static")
    end
  end

  context "when DataForSEO can't render the site" do
    it "says what DataForSEO said, keeps the plain-request checks, and files no phantom findings" do
      stub_fetches
      refused = DataForSeo::Error.new("DataForSEO task for on_page/instant_pages failed (40501): Invalid Field: 'custom_js'.", status_code: 40_501)
      data, client = run("https://www.acme.test" => refused, "https://www.acme.test/contact" => refused, paid: refused)

      home = data[:findings].find { |f| f[:key] == "pages:home-unreachable" }
      expect(home[:severity]).to eq("critical")
      expect(home[:body]).to include("Invalid Field: 'custom_js'")
      expect(data[:pages].first).to include(error: a_string_including("custom_js"), probe_ran: false)
      # The plain GETs still count.
      expect(data[:passed].map { |p| p[:key] }).to include("search:robots", "search:sitemap", "search:alt-host")
      # Nothing about a page nobody saw.
      expect(keys(data)).not_to include("calls:none", "search:viewport", "search:schema", "search:verification", "forms:absent:quote", "consent:embed-missing")
      expect(data[:phones][:checked]).to be(false)
      expect(data[:tracking][:checked]).to be(false)
      expect(data[:tracking][:managed].map { |m| m[:status] }.uniq).to eq([]).or eq(["unknown"])
      # custom_js is optional to `fetch`, so it is dropped and the page tried once more before the error surfaces.
      expect(client.calls.length).to eq(6)
    end
  end

  describe Reports::Dismissals do
    it "hides a dismissed key across runs and restores it" do
      findings = [{key: "search:verification"}, {key: "calls:none"}]
      expect(described_class.open(findings).length).to eq(2)
      described_class.dismiss!("search:verification", note: "verified via DNS")
      expect(described_class.open(findings).map { |f| f[:key] }).to eq(["calls:none"])
      expect(described_class.all["search:verification"]).to include("note" => "verified via DNS")
      described_class.restore!("search:verification")
      expect(described_class.open(findings).length).to eq(2)
    end
  end
end
