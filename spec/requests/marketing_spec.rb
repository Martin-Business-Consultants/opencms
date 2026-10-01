# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marketing pages", type: :request do
  before do
    Report.destroy_all; Agent.destroy_all; AgentRun.destroy_all; Setting.delete_all; Session.delete_all
    switch_plugin(:local_marketing, on: true)
  end

  let(:user) { create(:user) }

  it "renders the report with a scorecard, actions and the reports behind it" do
    Setting.set("reporting", "business_name" => "Acme", "domain" => "acme.com", "location_name" => "Austin,Texas,United States", "tracked_keywords" => ["a"])
    Setting.set("marketing", "business_type" => "self_storage")
    Report.create!(kind: "ranked_keywords", status: "complete", data: {"top_3" => 12, "total_count" => 250, "striking_distance" => [], "metrics" => {}})
    sign_in_as(user)

    get "/marketing"

    expect(response).to have_http_status(:ok)
    overview = Marketing::Overview.new
    expect(overview.business).to include(type: "self_storage", type_name: "Self storage", setup_complete: true)
    expect(overview.scorecard[:pillars].find { |p| p[:key] == "search" }[:score]).to eq(90)
    expect(overview.actions.map { |a| a[:key] }).to include("run:rank_map")
    expect(response.body).to include("Acme · Self storage", "Keywords in the top 3",
      ERB::Util.html_escape(overview.actions.find { |a| a[:key] == "run:rank_map" }[:title]))
    expect(response.body).not_to include("isn’t set up yet")
    expect(response.body).to include(report_path(Report.last))
    expect(response.body).to match(/Run the baseline \(about \$\d/)
  end

  it "the client view keeps only the owner's work and strips costs and agents" do
    Setting.set("reporting", "business_name" => "Acme", "domain" => "acme.com", "location_name" => "Austin,Texas,United States", "tracked_keywords" => ["a"])
    Report.create!(kind: "google_reviews", status: "complete", data: {"rating" => 4.2, "reviews_count" => 40, "unanswered" => 6, "fetched" => 20, "answered_pct" => 70, "low_unanswered" => [{"author" => "A", "text" => "Awful", "rating" => 1}]})
    sign_in_as(user)

    get "/marketing/client"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("What we need from you", "unanswered")
    expect(response.body).not_to include("$", "agent", "/reports/")
  end

  it "queues the template's reports as a baseline, once each" do
    Setting.set_secret("reporting", dataforseo_login: "u", dataforseo_password: "p")
    Setting.set("reporting", "business_name" => "Acme", "domain" => "acme.com", "location_name" => "Austin,Texas,United States",
                             "tracked_keywords" => ["a"], "audit_urls" => ["https://acme.com/"])
    Setting.set("marketing", "business_type" => "self_storage")
    sign_in_as(user)

    # The self-storage template's report list, site audit included.
    expect { post "/marketing/baseline" }.to have_enqueued_job(Report::RunJob).exactly(11).times
    expect(Report.in_flight.count).to eq(11)
    expect(flash[:notice]).to match(/Queued 11 reports/)

    post "/marketing/baseline"
    expect(Report.in_flight.count).to eq(11)
  end

  it "hands work to an agent: installs the template if needed and queues one run, without enabling it" do
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
    sign_in_as(user)

    post "/marketing/hand_off", params: {template: "metadata_optimizer", finding_id: 1}

    agent = Agent.find_by(template_key: "metadata_optimizer")
    expect(agent).to be_present
    expect(agent.enabled).to be(false)
    expect(AgentRun.where(agent: agent).count).to eq(1)
    expect(flash[:notice]).to match(/Handed to/)
  end

  it "guided setup writes settings, applies the template, and lands on the report" do
    sign_in_as(user)

    get "/marketing/setup", params: {type: "plumber", city: "Austin"}
    expect(response).to have_http_status(:ok)
    keywords = response.body[%r{<textarea[^>]*name="setup\[tracked_keywords\]"[^>]*>(.*?)</textarea>}m, 1]
    expect(keywords.split("\n")).to include("plumber Austin", "emergency plumber near me")
    expect(response.body).to match(/name="setup\[map_grid_size\]"[^>]*value="7"|value="7"[^>]*name="setup\[map_grid_size\]"/)

    patch "/marketing/setup", params: {setup: {business_type: "plumber", business_name: "Acme Plumbing", domain: "acmeplumbing.com",
                                               location_name: "Austin,Texas,United States", tracked_keywords: "plumber Austin\nemergency plumber Austin",
                                               citation_directories: "yelp.com\nangi.com", targets: {reviews: "150"}, scaffold: "1", schedule: "0", run_baseline: "0"}}

    expect(response).to redirect_to("/marketing")
    expect(flash[:notice]).to match(/Set up as Plumber\. 4 draft pages created\./)
    expect(Reports::Profile.load.tracked_keywords).to eq(["plumber Austin", "emergency plumber Austin"])
    expect(Setting.get("marketing")["business_type"]).to eq("plumber")
    expect(Marketing::Targets.all(Marketing::BusinessRegistry.current)["reviews"]).to eq(150.0)
    expect(Page.where(status: "draft").count).to eq(4)
  end

  it "needs reports:run to spend or hand off" do
    sign_in_as(create(:user, admin: false, role: create(:role, permissions: ["reports:read"])))
    post "/marketing/baseline"
    expect(Report.count).to eq(0)
    post "/marketing/hand_off", params: {template: "metadata_optimizer"}
    expect(Agent.count).to eq(0)
  end
end
