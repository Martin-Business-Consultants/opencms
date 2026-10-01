# frozen_string_literal: true

require "rails_helper"

# The Local Marketing plugin (engines/local_marketing): where it sits among the
# core's things, what disappears when it's off, and the reports as text. The
# pages are covered by spec/requests/{reports,marketing,site_audit}_spec.rb,
# the API by spec/requests/api/reports_spec.rb.
RSpec.describe "The Local Marketing plugin", type: :request do
  let(:admin) { create(:user) }

  def api_headers = {"Authorization" => "Bearer #{admin.api_token.token}"}

  before { Report.delete_all }

  describe "switched on" do
    before do
      switch_plugin :local_marketing, on: true
      sign_in_as admin
    end

    # Automation is empty unless a plugin (Agents) fills it, so Marketing then
    # follows Structure.
    it "puts the Marketing group after Automation, and Reporting among the integrations" do
      get dashboard_path
      groups = menu_groups
      expect(groups.index("Marketing")).to eq(groups.index("Structure") + 1)
      expect(response.body).to include("Marketer’s report", reports_path)

      get settings_path
      main = response.body[%r{<main id="main">.*</main>}m]
      expect(main.index("/settings/reporting")).to be > main.index("/settings/github")
      expect(main.index("/settings/reporting")).to be < main.index("/settings/deploy")
    end

    it "places its capabilities, recipe and agent tools where the core had them" do
      expect(Permissions.catalog.keys.each_cons(2).to_a).to include(["Recommendations", "Reports"])
      expect(RecurringTasks::Catalog.all.map(&:key).last).to eq("report_refresh")
      expect(Cms::Plugins.enabled_agent_tools["read_reports"].map(&:tool_name)).to eq(%w[list_reports get_report])
    end

    it "says what a report found, in words and tables" do
      report = Report.create!(kind: "page_health", status: "complete", cost: 0.02,
                              data: {"average_score" => 72.5, "critical" => 1,
                                     "pages" => [{"url" => "https://acme.test/", "score" => 72.5, "issues" => ["no h1"]}],
                                     "warnings" => ["on_page refused 'x'; sent without."]})

      get report_path(report)

      expect(response.body).to include("Headline figures", "72.5", "first snapshot")
      expect(response.body).to include("What this run couldn’t do", "refused")
      expect(response.body).to include("Pages", "https://acme.test/", "no h1")
      expect(response.body).not_to include("<svg", "<canvas")
    end

    it "runs a report as a resource at the old URL" do
      post run_reports_path(kind: "page_health")
      expect(response).to redirect_to(settings_reporting_path)
      expect(flash[:alert]).to be_present
    end

    it "gives the Scripts page the latest audit's verdict when Consent & Scripts is on" do
      expect(Cms::Plugins.provided(:site_audit)).to eq(LocalMarketing::SiteAudit)
      expect(LocalMarketing::SiteAudit.script_statuses).to be_nil
    end
  end

  describe "switched off" do
    before do
      switch_plugin :local_marketing, on: false
      sign_in_as admin
    end

    it "hides its pages, API, settings and menu" do
      [reports_path, marketing_path, marketing_client_path, marketing_setup_path, settings_reporting_path].each do |path|
        get path
        expect(response).to have_http_status(:not_found), path
      end
      post run_reports_path(kind: "page_health")
      expect(response).to have_http_status(:not_found)

      get "/api/reports", headers: api_headers
      expect(response).to have_http_status(:not_found)

      get dashboard_path
      expect(response.body).not_to include("Marketer’s report", "Site audit")
      get settings_path
      expect(response.body).not_to include("/settings/reporting")
      expect(Permissions.catalog).not_to have_key("Reports")
      expect(Cms::Plugins.enabled_agent_tools).not_to have_key("read_reports")
    end

    it "takes read_reports out of what an agent's run is told, but keeps it on the agent" do
      switch_plugin :ai, on: true
      switch_plugin :agents, on: true
      agent = Agent.create!(name: "Analyst", instructions: "Read reports.", capability_keys: %w[read_pages read_reports])

      expect(Agents::CapabilityCatalog.groups["Read"]).not_to have_key("read_reports")
      brief = Agents::RunBrief.new(agent).to_h
      expect(brief[:capabilities].map { it[:key] }).to eq(%w[read_pages])
      expect(brief[:required_capabilities]).not_to include("reports:read")

      # Saving the agent (the builder doesn't offer the switched-off key) keeps it.
      get edit_agent_path(agent)
      expect(response.body).to include(%(name="agent[capability_keys][]" value="read_reports"))
      agent.update!(name: "Analyst 2")
      expect(agent.reload.capability_keys).to include("read_reports")
    end

    it "leaves the Scripts page without an audit line" do
      get scripts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Check the site", "against the live site")
    end
  end

  it "is adopted on an install that already has reports" do
    Setting.delete_key("plugins")
    Current.plugin_states = nil
    Current.plugin_adoptions = nil
    Report.create!(kind: "page_health", status: "complete", data: {})

    expect(Cms::Plugins.enabled?(:local_marketing)).to be(true)
  end
end
