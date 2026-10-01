# frozen_string_literal: true

require "rails_helper"

# The Agents and AI plugins (engines/agents, engines/ai): where they sit, what
# disappears when they're off, and how an upgrade keeps an install that used
# them. The worker protocol is spec/requests/api/agent_runs_spec.rb; the
# roster, swarms and live view have their own specs.
RSpec.describe "The Agents and AI plugins", type: :request do
  let(:admin) { create(:user) }

  def api_headers(user = admin) = {"Authorization" => "Bearer #{user.api_token.token}"}

  def make_agent(name = "Sweep") = Agent.create!(name: name, instructions: "Look around.", capability_keys: %w[read_pages])

  describe "switched on" do
    before do
      switch_plugin :ai, on: true
      switch_plugin :agents, on: true
      sign_in_as admin
    end

    it "shows a run with its transcript, what it filed, and cancels it" do
      run = make_agent.dispatch!(trigger: "manual")
      run.update!(status: "running", started_at: Time.current, transcript: [{"kind" => "step", "text" => "read 40 pages"}])
      Recommendation.create!(kind: "metadata", title: "Title too long", agent_run: run)

      get agent_run_path(run)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("read 40 pages", "Title too long", "The brief it was given", "Cancel")

      post agent_run_cancellation_path(run)
      expect(response).to redirect_to(agent_run_path(run))
      expect(run.reload.cancel_requested).to be(true)
      expect(AuditLog.last.action).to eq("agent_run.canceled")
    end

    it "lists runs filtered by status and agent" do
      agent = make_agent
      other = make_agent("Other")
      agent.dispatch!(trigger: "manual")
      other.dispatch!(trigger: "manual").update!(status: "failed", error: "boom")

      get agent_runs_path, params: {status: "failed"}
      expect(response.body).to include("boom")
      expect(response.body).not_to include(%(id="agent_run_#{agent.agent_runs.first.id}"))
    end

    it "creates and shows a swarm with its seats" do
      agent = make_agent

      post swarms_path, params: {swarm: {name: "SEO", swarm_members_attributes: {"n1" => {agent_id: agent.id, frequency: "weekly", day: 3, hour: 10, enabled: "1"}}}}

      swarm = Swarm.find_by!(name: "SEO")
      expect(response).to redirect_to(swarm_path(swarm))
      get swarm_path(swarm)
      expect(response.body).to include("Sweep", "Wed · 10:00", "This cycle")
    end

    it "re-renders a swarm that won't save" do
      post swarms_path, params: {swarm: {name: ""}}
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "puts what the agents are doing in the header" do
      make_agent.dispatch!(trigger: "manual").update!(status: "running")

      get dashboard_path
      expect(response.body).to include("agents-ticker", "1 in flight")
    end

    it "sits in the admin menu under Automation" do
      get dashboard_path
      expect(menu_groups).to include("Automation")
      expect(menu_labels.index("Agents")).to eq(menu_labels.index("Developers") + 1)
      expect(submenu_labels("Agents")).to include("All agents", "Swarms", "Runs", "Templates")
    end

    it "names the agent that filed a finding, in the API and on the finding" do
      run = make_agent.dispatch!(trigger: "manual")

      post "/api/recommendations", params: {recommendation: {kind: "metadata", title: "Long title", agent_run_id: run.id}},
        headers: api_headers, as: :json
      expect(JSON.parse(response.body).dig("recommendation", "agent")).to eq("Sweep")

      get recommendation_path(Recommendation.last)
      expect(response.body).to include("from Sweep", agent_run_path(run))
    end
  end

  describe "switched off" do
    before do
      switch_plugin :agents, on: false
      switch_plugin :ai, on: false
      sign_in_as admin
    end

    it "takes its pages, API, Menu entries and header line away, and the core still works" do
      [agents_path, swarms_path, agent_runs_path, agent_runs_live_path, agent_templates_path, settings_ai_path].each do |path|
        get path
        expect(response).to have_http_status(:not_found), "#{path} answered #{response.status}"
      end
      get "/api/agent_runs", headers: api_headers
      expect(response).to have_http_status(:not_found)
      post "/api/agent_runs/claim", headers: api_headers
      expect(response).to have_http_status(:not_found)

      get dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("agents-ticker", agents_path)
      get settings_path
      expect(response.body).not_to include(settings_ai_path)
    end

    it "keeps findings working, without saying who filed them" do
      post "/api/recommendations", params: {recommendation: {kind: "metadata", title: "Long title", agent_run_id: 12}},
        headers: api_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body).dig("recommendation", "agent")).to be_nil
      get approvals_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "waits while the AI plugin it depends on is off" do
    switch_plugin :ai, on: false
    switch_plugin :agents, on: true

    expect(Cms::Plugins.enabled?(:agents)).to be(false)
    expect(Cms::Plugins.missing_dependencies(:agents)).to eq([:ai])
  end

  # An install that had agents before they were a plugin keeps them — and
  # the AI plugin they run on — without anyone switching anything.
  it "is adopted, with AI, by an install that already has agents" do
    make_agent

    expect(Cms::Plugins.enabled?(:agents)).to be(true)
    expect(Setting.get("plugins")).to include("agents" => true, "ai" => true)
  end

  it "doesn't adopt AI on its own when nothing was using it" do
    expect(Cms::Plugins.enabled?(:ai)).to be(false)
    expect(Setting.get("plugins")).not_to have_key("ai")
  end

  it "installs the template library the first time it's switched on" do
    AgentTemplate.delete_all
    SwarmTemplate.delete_all

    switch_plugin :ai, on: true
    switch_plugin :agents, on: true

    expect(AgentTemplate.count).to be_positive
    expect(SwarmTemplate.count).to be_positive
  end

  it "queues its scheduler every minute and its reaper every other minute" do
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
    even = Time.utc(2026, 9, 1, 12, 2)
    odd = Time.utc(2026, 9, 1, 12, 3)

    expect(Cms::Plugins.due_minutely_tasks(even).map(&:first)).to include("agents:scheduler", "agents:reaper")
    expect(Cms::Plugins.due_minutely_tasks(odd).map(&:first)).to include("agents:scheduler")
    expect(Cms::Plugins.due_minutely_tasks(odd).map(&:first)).not_to include("agents:reaper")

    expect { PluginsMinutelyJob.perform_now(at: even) }
      .to have_enqueued_job(Agent::ScheduleJob).and have_enqueued_job(AgentRun::ReapJob)
  end

  it "hands a finding's work to the library agent that does it" do
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
    agents = Cms::Plugins.provided(:agents)

    run = agents.hand_off("metadata_optimizer", triggered_by: admin)

    expect(run).to be_queued
    expect(Agent.find_by!(template_key: "metadata_optimizer")).not_to be_enabled
    expect(agents.hand_off("no_such_template", triggered_by: admin)).to be_nil
  end
end
