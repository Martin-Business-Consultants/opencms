# frozen_string_literal: true

require "rails_helper"

# The dashboard's fixable list and the person's answer to each item.
RSpec.describe "Site audit on the dashboard", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in_as user
    Report.delete_all
    Setting.delete_key("site_audit")
    switch_plugin(:local_marketing, on: true)
  end

  def audit_report
    Report.create!(kind: "site_audit", status: "complete", completed_at: Time.current, data: {
      "base_url" => "https://www.acme.test",
      "findings" => [
        {"key" => "consent:embed-missing", "area" => "consent", "severity" => "critical", "title" => "Consent banner is switched on but isn't on the live site", "body" => "…", "fix" => {"label" => "Get the embed", "href" => "/settings/consent"}},
        {"key" => "search:verification", "area" => "search", "severity" => "medium", "title" => "No Search Console verification tag found", "body" => "…", "fix" => {"label" => "In the site's code"}}
      ],
      "passed" => [{"key" => "pages:home", "area" => "pages", "title" => "Home page loads (200)"}],
      "counts" => {"critical" => 1, "high" => 0, "medium" => 1, "low" => 0}
    })
  end

  # The dashboard says what the audit found, as text; the fixable list lives
  # under Reports while it's rethought.
  it "says how many findings are open, and stops counting a dismissed one" do
    audit_report

    get dashboard_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("2 open findings", "1 critical, 1 medium", "https://www.acme.test")

    post "/reports/site_audit/dismissals/search:verification", params: {note: "verified via DNS"}
    expect(response).to have_http_status(:redirect)
    get dashboard_path
    expect(response.body).to include("1 open finding", "(1 dismissed)")

    delete "/reports/site_audit/dismissals/search:verification"
    get dashboard_path
    expect(response.body).to include("2 open findings")
  end

  it "says the audit has never run, and what it needs, when there is no snapshot" do
    Setting.set("general", "site_base_url" => "")
    get dashboard_path
    expect(response.body).to include("No audit has run yet.", "It needs: Audit urls.")
  end

  it "feeds the serious findings into the Marketer's Report as actions, minus dismissed ones" do
    audit_report
    actions = Marketing::Actions.new(profile: Reports::Profile.load).all
    audit_actions = actions.select { |a| a[:key].start_with?("audit:") }
    expect(audit_actions.map { |a| a[:key] }).to eq(["audit:consent:embed-missing"]) # medium isn't an action
    expect(audit_actions.first).to include(owner: "you", impact: 5)
    expect(audit_actions.first[:action]).to eq(type: "link", href: "/settings/consent", label: "Get the embed")

    Reports::Dismissals.dismiss!("consent:embed-missing")
    expect(Marketing::Actions.new(profile: Reports::Profile.load).all.none? { |a| a[:key].start_with?("audit:") }).to be(true)
  end

  it "lists the audit's open findings with their fixes, and the dismissed ones apart" do
    report = audit_report
    Reports::Dismissals.dismiss!("search:verification")
    get "/reports/#{report.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("1 open, 1 dismissed, 1 passed", "Get the embed", "Home page loads (200)")
    open, dismissed = response.body.split("<h2 class=\"txt-medium font-weight-bold margin-none\">Dismissed</h2>")
    expect(open).to include("Consent banner is switched on", "Not a problem here")
    expect(dismissed).to include("No Search Console verification tag found", "Restore")
  end

  it "leaves the dashboard alone while Local Marketing is off" do
    audit_report
    switch_plugin(:local_marketing, on: false)
    get dashboard_path
    expect(response.body).not_to include("Site audit")
    get "/reports"
    expect(response).to have_http_status(:not_found)
  end

  context "as an editor" do
    let(:user) { create(:user, admin: false, role: create(:role, permissions: Permissions.defaults_for(:editor))) }

    it "sees no audit card and can't dismiss" do
      audit_report
      get dashboard_path
      expect(response.body).not_to include("Site audit")
      post "/reports/site_audit/dismissals/search:verification"
      expect(response).to have_http_status(:redirect)
      expect(Reports::Dismissals.all).to eq({})
    end
  end
end
