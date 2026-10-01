# frozen_string_literal: true

require "rails_helper"

# What an agent sees of the reports: the latest of each with movement, and
# any one in full — and, deliberately, no way to run one.
RSpec.describe "API reports", type: :request do
  before do
    Report.destroy_all
    switch_plugin(:local_marketing, on: true)
  end

  let(:user) { create(:user) }
  let(:headers) { {"Authorization" => "Bearer #{user.api_token.token}", "Accept" => "application/json"} }

  def json = JSON.parse(response.body)

  it "lists the latest snapshot of each kind with how each figure moved, and names what was never run" do
    Report.create!(kind: "page_health", status: "complete", data: {"average_score" => 84.0, "pages" => []}, created_at: 8.days.ago)
    Report.create!(kind: "page_health", status: "complete", data: {"average_score" => 61.0, "pages" => [], "warnings" => ["x refused 'y'; sent without."]})
    Report.create!(kind: "page_health", status: "failed", created_at: 1.hour.ago)

    get "/api/reports", headers: headers

    expect(response).to have_http_status(:ok)
    row = json["reports"].find { |r| r["kind"] == "page_health" }
    score = row["metrics"].find { |m| m["key"] == "average_score" }
    expect(score).to include("now" => 61.0, "previous" => 84.0, "good" => "up")
    expect(row["previous_at"]).to be_present
    expect(row["warnings"]).to eq(["x refused 'y'; sent without."])
    expect(json["never_run"]).to include("ranked_keywords", "citations")
    expect(json["never_run"]).not_to include("page_health")
  end

  it "returns one report in full, and the one before it on request" do
    Report.create!(kind: "llm_visibility", status: "complete", data: {"mentions" => 3}, created_at: 8.days.ago)
    Report.create!(kind: "llm_visibility", status: "complete", data: {"mentions" => 9})

    get "/api/reports/llm_visibility", headers: headers
    expect(json.dig("report", "data", "mentions")).to eq(9)

    get "/api/reports/llm_visibility?previous", headers: headers
    expect(json.dig("report", "data", "mentions")).to eq(3)
  end

  it "says plainly when a kind is unknown or has never run" do
    get "/api/reports/not_a_thing", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(json["kinds"]).to include("ranked_keywords")

    get "/api/reports/backlinks", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(json["note"]).to match(/never been run/)
  end

  it "is read-only — there is no way to run a report from here" do
    post "/api/reports", headers: headers, params: {kind: "page_health"}
    expect(response).to have_http_status(:not_found)
    post "/api/reports/page_health/run", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "needs reports:read" do
    restricted = create(:user, admin: false, role: create(:role, permissions: ["pages:read"]))
    get "/api/reports", headers: {"Authorization" => "Bearer #{restricted.api_token.token}"}
    expect(response).to have_http_status(:forbidden)
  end

  it "the agent library grants read_reports to the Reporting Analyst, and the catalogue maps it to reports:read" do
    Agents::Registry.reload!
    template = Agents::Registry.find("reporting_analyst")
    expect(template).to be_present
    expect(template.capabilities).to include("read_reports")
    expect(Agents::CapabilityCatalog.capabilities_for(["read_reports"])).to eq(["reports:read"])
    # An installed agent starts disabled: turning it on is the person's act.
    expect(Agent.new(template.to_agent_attributes).enabled).to be(false)
  end
end
