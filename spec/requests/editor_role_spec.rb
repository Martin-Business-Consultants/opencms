# frozen_string_literal: true

require "rails_helper"

# Reports and agents are the administrator's. The default Editor role writes
# and publishes content and sees neither — and still has its review queue.
RSpec.describe "The default Editor role", type: :request do
  # Start from a clean queue: the seeded roles and findings aren't this spec's.
  before { Session.delete_all; Recommendation.destroy_all; Role.where(name: %w[Editor Author]).destroy_all }

  let(:editor_role) { SiteBootstrap.install_human_roles!; Role.find_by!(name: "Editor") }
  let(:editor) { create(:user, admin: false, role: editor_role) }

  it "is installed at bootstrap with no reports, agents or findings capabilities" do
    SiteBootstrap.install_human_roles!
    role = Role.find_by!(name: "Editor")
    expect(role.system).to be(false)
    expect(role.permissions).to include("pages:publish", "entries:publish", "globals:write")
    expect(role.permissions.grep(/\A(reports|agents|recommendations):/)).to be_empty
    expect(Role.find_by!(name: "Author").permissions.grep(/\A(reports|agents|recommendations):/)).to be_empty
    # Idempotent, and never overwrites an admin's later edits.
    role.update!(permissions: role.permissions + ["reports:read"])
    SiteBootstrap.install_human_roles!
    expect(Role.find_by!(name: "Editor").permissions).to include("reports:read")
  end

  it "keeps the machine Agent role able to do its job" do
    expect(Permissions::AGENT_DEFAULT).to include("recommendations:write")
    # `reports:read` is Local Marketing's to grant, and never `reports:run`.
    switch_plugin :local_marketing, on: true
    expect(Permissions.defaults_for(:agent)).to include("reports:read")
    expect(Permissions.defaults_for(:agent)).not_to include("reports:run")
    # `agents:run` is the Agents plugin's to grant (its permission defaults).
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
    expect(Permissions.defaults_for(:agent)).to include("agents:read", "agents:run")
  end

  it "is turned away from the Marketing group, the reports and the agents" do
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
    switch_plugin :local_marketing, on: true
    sign_in_as(editor)

    get "/marketing"
    expect(response).to redirect_to(dashboard_path)
    get "/reports"
    expect(response).to redirect_to(dashboard_path)
    get "/agents"
    expect(response).to redirect_to(dashboard_path)
    get "/recommendations"
    expect(response).to redirect_to(dashboard_path)
    post "/reports/page_health/run"
    expect(Report.count).to eq(0)
  end

  it "still has the review queue — without the agents' findings in it" do
    Recommendation.create!(kind: "metadata", title: "A finding", impact: 3)
    sign_in_as(editor)

    get "/approvals"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Agent findings", "A finding")

    get "/pages"
    expect(response).to have_http_status(:ok)
  end

  it "an admin's queue keeps the findings" do
    Recommendation.create!(kind: "metadata", title: "A finding", impact: 3)
    sign_in_as(create(:user))

    get "/approvals"
    expect(response.body).to include("Agent findings", "A finding")
  end

  it "the API refuses the editor's token for reports too" do
    switch_plugin :local_marketing, on: true
    get "/api/reports", headers: {"Authorization" => "Bearer #{editor.api_token.token}"}
    expect(response).to have_http_status(:forbidden)
  end
end
