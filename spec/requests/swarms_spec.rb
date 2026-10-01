# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Swarms", type: :request do
  before do
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
  end

  def sign_in_with(capabilities)
    sign_in_as(create(:user, admin: false, role: create(:role, permissions: capabilities)))
  end

  def make_agent(name)
    Agent.create!(name: name, instructions: "Work.", capability_keys: %w[read_pages])
  end

  describe "GET /swarms" do
    it "lists swarms with their rota" do
      swarm = Swarm.create!(name: "SEO", enabled: true)
      swarm.swarm_members.create!(agent: make_agent("Meta"), frequency: "weekly", day: 1, hour: 9)

      sign_in_with(["agents:read"])
      get "/swarms"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("SEO", "Meta · Mon · 09:00")
    end

    it "refuses someone without agents:read" do
      sign_in_with(["pages:read"])

      get "/swarms"

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST /swarms/:id/run" do
    it "queues a run per enabled seat" do
      swarm = Swarm.create!(name: "SEO")
      swarm.swarm_members.create!(agent: make_agent("A"), frequency: "weekly", day: 1, hour: 9)
      swarm.swarm_members.create!(agent: make_agent("B"), frequency: "weekly", day: 3, hour: 9, enabled: false)

      sign_in_with(["agents:read", "agents:run"])

      expect { post "/swarms/#{swarm.id}/run" }.to change { AgentRun.count }.by(1)
      expect(AgentRun.last.swarm).to eq(swarm)
    end

    it "says so when every seat is disabled rather than silently doing nothing" do
      swarm = Swarm.create!(name: "SEO")
      swarm.swarm_members.create!(agent: make_agent("A"), frequency: "daily", hour: 9, enabled: false)

      sign_in_with(["agents:read", "agents:run"])
      post "/swarms/#{swarm.id}/run"

      expect(flash[:alert]).to include("every seat")
    end
  end

  describe "installing a swarm template" do
    before do
      Agents::TemplateLibrary.seed!
      Agents::SwarmTemplateLibrary.seed!
    end

    it "stands up the swarm and the agents it needs, all paused" do
      sign_in_with(["agents:read", "agents:write"])
      template = SwarmTemplate.find_by!(template_key: "technical_health")

      expect { post "/swarm_templates/#{template.id}/installation" }.to change { Swarm.count }.by(1)

      swarm = Swarm.find_by!(template_key: "technical_health")
      expect(swarm).not_to be_enabled
      expect(swarm.swarm_members.count).to eq(template.member_rows.size)
      expect(swarm.agents.map(&:enabled)).to all(be(false))
    end

    it "refuses when the roster names agent templates that aren't installed" do
      sign_in_with(["agents:read", "agents:write"])
      template = SwarmTemplate.find_by!(template_key: "technical_health")
      AgentTemplate.where(template_key: "technical_seo").destroy_all

      expect { post "/swarm_templates/#{template.id}/installation" }.not_to change { Swarm.count }
      expect(flash[:alert]).to include("aren't installed")
    end
  end

  describe "DELETE /swarms/:id" do
    # A swarm is a rota over agents, not a container for them.
    it "removes the seats but keeps the agents" do
      swarm = Swarm.create!(name: "SEO")
      swarm.swarm_members.create!(agent: make_agent("Keep me"), frequency: "daily", hour: 9)

      sign_in_with(["agents:read", "agents:delete"])
      delete "/swarms/#{swarm.id}"

      expect(Swarm.find_by(id: swarm.id)).to be_nil
      expect(Agent.find_by(name: "Keep me")).to be_present
    end
  end
end
