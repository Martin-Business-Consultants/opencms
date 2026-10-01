# frozen_string_literal: true

require "rails_helper"

# Reporting spends real money per run, so most of what matters here is the
# guards: you can't run without a credential, you can't run a report whose
# inputs are missing, and you can't pay twice for one answer.
RSpec.describe "Reporting", type: :request do
  before do
    Report.destroy_all
    Setting.delete_all
    Session.delete_all
    switch_plugin(:local_marketing, on: true)
  end

  let(:user) { create(:user) }

  def configure!(**overrides)
    Setting.set_secret("reporting", dataforseo_login: "u@example.com", dataforseo_password: "p")
    Setting.set("reporting", {
      "business_name" => "Acme Storage",
      "domain" => "acme.co.uk",
      "location_name" => "Cardiff,Wales,United Kingdom",
      "tracked_keywords" => ["storage cardiff"],
      "audit_urls" => ["https://acme.co.uk/"]
    }.merge(overrides.stringify_keys))
  end

  describe "GET /reports" do
    it "lists every report in the catalog, run or not" do
      sign_in_as(user)

      get "/reports"

      expect(response).to have_http_status(:ok)
      Reports::Catalog.all.each { |definition| expect(response.body).to include(ERB::Util.html_escape(definition.title)) }
      expect(response.body).to include("Never")
    end

    it "says each report's headline figures, how they moved, and what the window cost" do
      sign_in_as(user)
      Report.create!(kind: "page_health", status: "complete", cost: 0.03,
                     data: {"average_score" => 70.0, "pages" => []}, created_at: 3.days.ago)
      Report.create!(kind: "page_health", status: "complete", cost: 0.03,
                     data: {"average_score" => 80.0, "pages" => []})

      get "/reports", params: {range: "30d"}

      expect(response.body).to include("<strong>80.0</strong>", "up 10.0 (better)")
      expect(response.body).to include("In this window: $0.060 across 2 runs")
      expect(response.body).to include("Last 30 days")
    end

    it "is refused without reports:read" do
      sign_in_as(create(:user, admin: false, role: create(:role, permissions: ["pages:read"])))

      get "/reports"

      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "POST /reports/:kind/run" do
    it "sends the person to settings rather than failing silently with no credential" do
      sign_in_as(user)

      post "/reports/llm_visibility/run"

      expect(response).to redirect_to(settings_reporting_path)
      expect(flash[:alert]).to match(/DataForSEO credentials/)
      expect(Report.count).to eq(0)
    end

    it "refuses a report whose inputs are missing, and says which" do
      configure!(tracked_keywords: [])
      sign_in_as(user)

      post "/reports/local_rankings/run"

      expect(response).to redirect_to(settings_reporting_path)
      expect(flash[:alert]).to match(/tracked keywords/i)
      expect(Report.count).to eq(0)
    end

    it "rejects a report kind that isn't in the catalog" do
      configure!
      sign_in_as(user)

      post "/reports/not_a_report/run"

      expect(response).to redirect_to(reports_path)
      expect(Report.count).to eq(0)
    end

    it "queues the run and snapshots the profile as it was" do
      configure!
      sign_in_as(user)

      expect { post "/reports/llm_visibility/run" }
        .to have_enqueued_job(Report::RunJob)

      report = Report.last
      expect(report.kind).to eq("llm_visibility")
      expect(report.status).to eq("queued")
      expect(report.requested_by).to eq(user)
      # Denormalized on purpose — a later settings change must not relabel
      # this run's history.
      expect(report.params["tracked_keywords"]).to eq(["storage cardiff"])
      expect(response).to redirect_to(report_path(report))
    end

    it "will not pay twice for one answer" do
      configure!
      sign_in_as(user)
      post "/reports/llm_visibility/run"
      existing = Report.last

      expect { post "/reports/llm_visibility/run" }.not_to change(Report, :count)
      expect(response).to redirect_to(report_path(existing))
      expect(flash[:notice]).to match(/already running/)
    end

    it "is refused without reports:run, even with reports:read" do
      configure!
      sign_in_as(create(:user, admin: false, role: create(:role, permissions: ["reports:read"])))

      post "/reports/llm_visibility/run"

      expect(Report.count).to eq(0)
    end
  end

  describe "GET /reports/:id" do
    it "renders the snapshot with nothing to compare against on a first run" do
      sign_in_as(user)
      report = Report.create!(kind: "llm_visibility", status: "complete",
                              data: {"mentions" => 3}, cost: 0.02)

      get "/reports/#{report.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("AI visibility", "first snapshot, so there is nothing to compare with")
    end

    it "compares with the run before and lists the snapshots in the window" do
      sign_in_as(user)
      old = Report.create!(kind: "llm_visibility", status: "complete", cost: 0.02,
                           data: {"mentions" => 3, "ai_search_volume" => 10, "platforms" => []},
                           created_at: 40.days.ago)
      newer = Report.create!(kind: "llm_visibility", status: "complete", cost: 0.02,
                             data: {"mentions" => 8, "ai_search_volume" => 30,
                                    "platforms" => [{"key" => "chat_gpt", "mentions" => 5}]})
      Report.create!(kind: "llm_visibility", status: "failed", created_at: 2.days.ago)
      Report.create!(kind: "llm_visibility", status: "complete", data: {"mentions" => 1},
                     created_at: 200.days.ago)

      ancient = Report.complete.order(:created_at).first

      get "/reports/#{newer.id}"

      expect(response.body).to include("<strong>8</strong>", "up 5 (better)")
      expect(response.body).to include("Snapshots in this window", report_path(old))
      expect(response.body).not_to include(report_path(ancient))
      # The rows of a table-shaped part are listed too.
      expect(response.body).to include("Platforms", "chat_gpt")
    end

    it "honours the range on the URL" do
      sign_in_as(user)
      Report.create!(kind: "llm_visibility", status: "complete", data: {}, created_at: 40.days.ago)
      current = Report.create!(kind: "llm_visibility", status: "complete", data: {})

      get "/reports/#{current.id}", params: {range: "7d"}
      expect(response.body).not_to include("Snapshots in this window")

      get "/reports/#{current.id}", params: {from: 60.days.ago.to_date.iso8601}
      expect(response.body).to include("Snapshots in this window")
    end
  end

  describe "the settings page" do
    it "never sends a saved credential back to the form" do
      configure!
      Setting.set_secret("reporting", dataforseo_password: "pw-never-shown")
      sign_in_as(user)

      get "/settings/reporting"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("u@example.com")
      expect(response.body).not_to include("pw-never-shown")
      expect(response.body).to include("Saved — leave blank to keep")
    end

    it "treats a blank credential field as 'leave the saved one alone'" do
      configure!
      sign_in_as(user)

      patch "/settings/reporting", params: {
        settings: {dataforseo_login: "", dataforseo_password: "", business_name: "Acme Storage Ltd"}
      }

      expect(Setting.secret("reporting", :dataforseo_login)).to eq("u@example.com")
      expect(Setting.get("reporting")["business_name"]).to eq("Acme Storage Ltd")
    end

    it "splits a textarea into a list" do
      sign_in_as(user)

      patch "/settings/reporting", params: {
        settings: {tracked_keywords: "storage cardiff\nself storage\n\n storage cardiff "}
      }

      expect(Setting.get("reporting")["tracked_keywords"]).to eq(["storage cardiff", "self storage"])
    end
  end

  describe "PATCH /reports/citations/statuses/:directory" do
    it "records what a person did about a directory, without a run" do
      sign_in_as(user)

      patch "/reports/citations/statuses/yelp.com", params: {status: "submitted", note: "Sent 3 Sep"}, headers: {"HTTP_REFERER" => "/reports/1"}

      expect(response).to redirect_to("/reports/1")
      entry = Setting.get("citations")["yelp.com"]
      expect(entry).to include("status" => "submitted", "note" => "Sent 3 Sep", "updated_by" => user.email)
      expect(entry["updated_at"]).to be_present
      expect(Report.count).to eq(0)
    end

    it "rejects a status it doesn't know and keeps other directories' entries" do
      sign_in_as(user)
      Setting.set("citations", "bbb.org" => {"status" => "live"})

      patch "/reports/citations/statuses/yelp.com", params: {status: "done"}

      expect(flash[:alert]).to match(/Unknown status/)
      expect(Setting.get("citations").keys).to eq(["bbb.org"])
    end

    it "needs reports:run — managing citations is work on the business's behalf" do
      sign_in_as(create(:user, admin: false, role: create(:role, permissions: ["reports:read"])))

      patch "/reports/citations/statuses/yelp.com", params: {status: "live"}

      expect(Setting.get("citations")).to eq({})
    end
  end

  describe Report::RunJob do
    it "records the normalized data and what the call actually cost" do
      configure!
      report = Report.create!(kind: "llm_visibility")

      allow(DataForSeo::Client).to receive(:from_settings).and_return(
        instance_double(
          DataForSeo::Client,
          post: DataForSeo::Response.new(
            result: [{"aggregated_metrics" => {"total" => {"mentions" => 12, "ai_search_volume" => 40}}}],
            cost: 0.0234, task_id: "t", time: "1"
          ),
          # The report resolves its country before it asks anything else.
          get: [{"location_code" => 2826, "location_name" => "United Kingdom",
                 "available_languages" => [{"language_code" => "en"}]}]
        )
      )

      described_class.new.perform(report.id, tenant: "reports")

      report.reload
      expect(report.status).to eq("complete")
      expect(report.data["mentions"]).to eq(12)
      expect(report.data["location"]).to eq("United Kingdom")
      expect(report.data["location_is_fallback"]).to be(false)
      expect(report.data).not_to have_key("warnings")
      expect(report.cost.to_f).to eq(0.0234)
      expect(report.completed_at).to be_present
    end

    it "fails the report with the API's own message rather than leaving it running" do
      configure!
      report = Report.create!(kind: "llm_visibility")

      allow(DataForSeo::Client).to receive(:from_settings)
        .and_raise(DataForSeo::Error.new("DataForSEO error 40200: insufficient funds"))

      described_class.new.perform(report.id, tenant: "reports")

      report.reload
      expect(report.status).to eq("failed")
      expect(report.error).to match(/insufficient funds/)
      expect(report.completed_at).to be_present
    end

    it "does not re-run a report that is no longer queued" do
      configure!
      report = Report.create!(kind: "llm_visibility", status: "complete")

      expect(DataForSeo::Client).not_to receive(:from_settings)

      described_class.new.perform(report.id, tenant: "reports")

      expect(report.reload.status).to eq("complete")
    end
  end
end
