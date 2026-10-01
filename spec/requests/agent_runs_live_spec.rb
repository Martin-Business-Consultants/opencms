# frozen_string_literal: true

require "rails_helper"

# "Is anything working right now" is a different question from "what did this
# agent do last Tuesday", and the answer to the first has to be readable at a
# glance rather than found two hundred rows into a log.
RSpec.describe "Agent runs — live", type: :request do
  before do
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
  end

  def sign_in_with(capabilities)
    sign_in_as(create(:user, admin: false, role: create(:role, permissions: capabilities)))
  end

  let(:agent) { Agent.create!(name: "Metadata", instructions: "Fix titles.", capability_keys: %w[read_pages]) }

  def run(status:, transcript: [])
    AgentRun.create!(agent: agent, agent_name: agent.name, status: status, transcript: transcript)
  end

  it "separates what is in flight from what just finished, and refreshes itself" do
    running = run(status: "running")
    finished = run(status: "completed")

    sign_in_with(["agents:read"])
    get "/agent_runs/live"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(id="agent_run_#{running.id}"), "Just finished", "##{finished.id}", %(data-controller="refresh"))
  end

  # The step text is the whole value of this screen: "claimed 3 minutes ago"
  # says a run exists, and "reading /pricing" says it is working.
  it "shows the tail of the transcript for a run in flight" do
    steps = Array.new(12) { |i| {"kind" => "step", "text" => "step #{i}"} }
    run(status: "running", transcript: steps)

    sign_in_with(["agents:read"])
    get "/agent_runs/live"

    expect(response.body).to include("step 4", "step 11")
    expect(response.body).not_to include("step 3<")
  end

  it "refuses someone without agents:read" do
    sign_in_with(["pages:read"])

    get "/agent_runs/live"

    expect(response).not_to have_http_status(:success)
  end

  # "live" must never be read as an id, or this route quietly 404s the moment
  # someone adds a run.
  it "routes ahead of the show route" do
    expect(Rails.application.routes.recognize_path("/agent_runs/live"))
      .to include(controller: "agent_runs/lives", action: "show")
  end
end
