# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agents", type: :request do
  before do
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
  end

  def sign_in_with(capabilities)
    user = create(:user, admin: false, role: create(:role, permissions: capabilities))
    sign_in_as(user)
    user
  end

  let!(:agent) do
    Agent.create!(name: "Metadata", instructions: "Fix titles.", capability_keys: %w[read_pages write_pages])
  end

  describe "GET /agents" do
    it "renders the roster for a reader" do
      sign_in_with(["agents:read"])

      get "/agents"

      expect(response).to have_http_status(:success)
    end

    it "refuses someone without agents:read" do
      sign_in_with(["pages:read"])

      get "/agents"

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST /agents/:id/run" do
    # Running is a separate power from editing: a reviewer can execute the
    # roster without being able to rewrite what it executes.
    it "queues a run for someone with agents:run" do
      sign_in_with(["agents:read", "agents:run"])

      expect { post "/agents/#{agent.id}/run" }.to change { AgentRun.count }.by(1)
      expect(AgentRun.last).to be_queued
      expect(AgentRun.last.trigger).to eq("manual")
    end

    it "refuses someone who can only read" do
      sign_in_with(["agents:read"])

      expect { post "/agents/#{agent.id}/run" }.not_to change { AgentRun.count }
    end

    # "Disabled" means "not on a schedule", which is exactly when you want to
    # try one by hand.
    it "still runs a disabled agent by hand" do
      sign_in_with(["agents:read", "agents:run"])
      agent.update!(enabled: false)

      expect { post "/agents/#{agent.id}/run" }.to change { AgentRun.count }.by(1)
    end
  end

  describe "POST /agents (create)" do
    it "creates a paused agent with its scopes" do
      sign_in_with(["agents:read", "agents:write"])

      post "/agents", params: {
        agent: {
          name: "Link builder",
          instructions: "Add internal links.",
          capability_keys: ["read_pages", "write_pages"],
          content_scopes_attributes: [{scope_kind: "collection", value: "posts"}]
        }
      }

      created = Agent.find_by!(name: "Link builder")
      expect(created).not_to be_enabled
      expect(created.scope_label).to eq("collection “posts”")
    end
  end

  # The roster page's banner and its list come from one server-side answer
  # (Agents::RosterState), so they can't disagree about whether anything is
  # wrong.
  describe "the roster" do
    it "states the headline, the counts and each agent with its tier" do
      sign_in_with(["agents:read"])
      state = Agents::RosterState.new(agents: [agent], worker: Agents::WorkerHealth.new.to_h)

      get "/agents"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(state.headline), "enabled", "needs attention", "in flight")
      expect(response.body).to include("Metadata", agent.tier)
      expect(Ai::Models::TIERS).to include(agent.tier)
      expect(agent.budget.to_h.keys.map(&:to_s)).to match_array(%w[tool_rounds proposals context_tokens])
    end

    it "offers only what the role allows" do
      sign_in_with(["agents:read"])

      get "/agents"

      expect(response.body).not_to include("New agent", ">Run<")
    end
  end

  describe "editing" do
    it "re-renders the form with the errors" do
      sign_in_with(["agents:read", "agents:write"])

      post "/agents", params: {agent: {name: "", instructions: ""}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That didn’t work")
    end

    it "saves scopes and capabilities, and removes a scope that's ticked for removal" do
      sign_in_with(["agents:read", "agents:write"])
      scope = agent.content_scopes.create!(scope_kind: "path_prefix", value: "/blog")

      get "/agents/#{agent.id}/edit"
      expect(response.body).to include("/blog", "Add a scope")

      patch "/agents/#{agent.id}", params: {agent: {capability_keys: ["", "read_pages"],
        content_scopes_attributes: {"0" => {id: scope.id, _destroy: "1"}, "n1" => {scope_kind: "collection", value: "posts"}}}}

      expect(response).to redirect_to(agents_path)
      expect(agent.reload.capability_keys).to eq(["read_pages"])
      expect(agent.content_scopes.map(&:value)).to eq(["posts"])
    end
  end

  describe "POST /agents/:id/upgrade" do
    let!(:stale) do
      template = Agents::Registry.all.values.first
      Agent.create!(template.to_agent_attributes.merge(template_key: template.key, template_version: 0))
    end

    it "takes the shipped version and stamps it" do
      sign_in_with(["agents:read", "agents:write"])

      post "/agents/#{stale.id}/upgrade"

      expect(stale.reload.template_version).to eq(Agents::Registry.find(stale.template_key).version)
      expect(flash[:notice]).to include(stale.template_key)
    end

    # Nothing to take is not an error, and it must not read like one: the page
    # says so and leaves the agent alone.
    it "says so when there is nothing newer" do
      sign_in_with(["agents:read", "agents:write"])
      stale.update!(template_version: Agents::Registry.find(stale.template_key).version)

      post "/agents/#{stale.id}/upgrade"

      expect(flash[:alert]).to include("already on the newest version")
    end

    it "refuses someone who can only read" do
      sign_in_with(["agents:read"])

      post "/agents/#{stale.id}/upgrade"

      expect(stale.reload.template_version).to eq(0)
    end
  end

  describe "DELETE /agents/:id" do
    # A deleted agent must not erase the record of what it did.
    it "keeps the run history" do
      sign_in_with(["agents:read", "agents:delete"])
      run = agent.dispatch!

      delete "/agents/#{agent.id}"

      expect(Agent.find_by(id: agent.id)).to be_nil
      expect(run.reload.agent_id).to be_nil
      expect(run.agent_name).to eq("Metadata")
    end
  end

  describe "installing a template" do
    it "stands one up as a paused agent" do
      sign_in_with(["agents:read", "agents:write"])
      Agents::TemplateLibrary.seed!
      template = AgentTemplate.find_by!(template_key: "content_gap")

      expect { post "/agent_templates/#{template.id}/installation" }.to change { Agent.count }.by(1)

      installed = Agent.find_by!(template_key: "content_gap")
      expect(installed).not_to be_enabled
    end

    # Installing twice is legitimate — one scoped to /blog, one to /docs — and
    # agent names are unique, so the second must not simply fail.
    it "disambiguates the name on a second install" do
      sign_in_with(["agents:read", "agents:write"])
      Agents::TemplateLibrary.seed!
      template = AgentTemplate.find_by!(template_key: "content_gap")

      post "/agent_templates/#{template.id}/installation"
      expect { post "/agent_templates/#{template.id}/installation" }.to change { Agent.count }.by(1)
    end
  end
end
