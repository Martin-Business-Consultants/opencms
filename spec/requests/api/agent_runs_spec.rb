# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::AgentRuns", type: :request do
  before do
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
  end

  let(:agent) do
    Agent.create!(name: "Sweep", instructions: "Look around.", capability_keys: %w[read_pages])
  end

  def auth_headers(capabilities = ["agents:read", "agents:run"])
    actor = create(:user, admin: false, role: create(:role, permissions: capabilities))
    {"Authorization" => "Bearer #{actor.api_token.token}"}
  end

  def json = JSON.parse(response.body)

  describe "POST /api/agent_runs/claim" do
    it "401s without a token" do
      post "/api/agent_runs/claim"
      expect(response).to have_http_status(:unauthorized)
    end

    # `agents:run` is deliberately not implied by `agents:read` — reading the
    # roster and executing it are different powers.
    it "403s for a token that can read but not run" do
      post "/api/agent_runs/claim", headers: auth_headers(["agents:read"])
      expect(response).to have_http_status(:forbidden)
    end

    # A polling worker finding an empty queue is the normal case, not an
    # error — it must not look like a failure to retry logic.
    it "204s when nothing is queued" do
      post "/api/agent_runs/claim", headers: auth_headers
      expect(response).to have_http_status(:no_content)
    end

    it "returns the run, its brief and the endpoints to report against" do
      agent.dispatch!

      post "/api/agent_runs/claim", params: {worker: "box-1"}, headers: auth_headers
      expect(response).to have_http_status(:ok)

      run = json.fetch("agent_run")
      expect(run["status"]).to eq("claimed")
      expect(run["claimed_by"]).to eq("box-1")
      expect(run.dig("brief", "agent", "instructions")).to eq("Look around.")
      expect(run.dig("brief", "rules")).to be_present
      expect(run.dig("endpoints", "heartbeat")).to include("/heartbeat")
    end

    it "clamps an unreasonable lease request" do
      agent.dispatch!

      post "/api/agent_runs/claim", params: {worker: "box-1", lease_seconds: 99_999}, headers: auth_headers

      expires = Time.zone.parse(json.dig("agent_run", "lease_expires_at"))
      expect(expires).to be <= 1.hour.from_now + 5.seconds
    end
  end

  describe "the run lifecycle" do
    let(:headers) { auth_headers }

    def claim!
      agent.dispatch!
      post "/api/agent_runs/claim", params: {worker: "box-1"}, headers: headers
      AgentRun.find(json.dig("agent_run", "id"))
    end

    it "walks start → report → complete" do
      run = claim!

      post "/api/agent_runs/#{run.id}/start", headers: headers
      expect(response).to have_http_status(:ok)

      post "/api/agent_runs/#{run.id}/report",
        params: {kind: "tool", message: "read 12 pages"}, headers: headers
      expect(response).to have_http_status(:accepted)

      post "/api/agent_runs/#{run.id}/complete",
        params: {summary: "Rewrote 3 titles", input_tokens: 100, output_tokens: 20}, headers: headers
      expect(response).to have_http_status(:ok)

      run.reload
      expect(run).to be_completed
      expect(run.summary).to eq("Rewrote 3 titles")
      expect(run.transcript.first["message"]).to eq("read 12 pages")
    end

    it "409s when advancing a run that is no longer the worker's" do
      run = claim!
      post "/api/agent_runs/#{run.id}/start", headers: headers
      post "/api/agent_runs/#{run.id}/complete", params: {summary: "done"}, headers: headers

      post "/api/agent_runs/#{run.id}/complete", params: {summary: "again"}, headers: headers

      expect(response).to have_http_status(:conflict)
      expect(json["status"]).to eq("completed")
    end

    describe "heartbeat" do
      it "tells a healthy worker to continue" do
        run = claim!
        post "/api/agent_runs/#{run.id}/start", headers: headers

        post "/api/agent_runs/#{run.id}/heartbeat", headers: headers

        expect(json["continue"]).to be(true)
        expect(json["lease_expires_at"]).to be_present
      end

      # The stop signal. Without it a canceled run keeps burning tokens on a
      # worker that has no way to know.
      it "tells a canceled run's worker to stop" do
        run = claim!
        post "/api/agent_runs/#{run.id}/start", headers: headers
        run.request_cancel!

        post "/api/agent_runs/#{run.id}/heartbeat", headers: headers

        expect(json["continue"]).to be(false)
        expect(json["reason"]).to eq("canceled")
      end

      it "tells a reaped worker its run is gone" do
        run = claim!
        post "/api/agent_runs/#{run.id}/start", headers: headers
        run.update!(lease_expires_at: 1.minute.ago)
        AgentRun.reap!

        post "/api/agent_runs/#{run.id}/heartbeat", headers: headers

        expect(json["continue"]).to be(false)
        expect(json["reason"]).to include("no longer yours")
      end
    end

    it "records a failure with its reason" do
      run = claim!
      post "/api/agent_runs/#{run.id}/start", headers: headers

      post "/api/agent_runs/#{run.id}/fail", params: {error: "CMS returned 500"}, headers: headers

      expect(response).to have_http_status(:ok)
      expect(run.reload).to be_failed
      expect(run.error).to eq("CMS returned 500")
    end
  end
end
