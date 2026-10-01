# frozen_string_literal: true

require "rails_helper"

# Settings › Updates over the API: read and check, never start. Starting an
# update restarts the whole install, so it's an admin's click in the admin.
RSpec.describe "API: updates", type: :request do
  let(:admin) { create(:user) }
  let(:agent) { create(:user, admin: false, role: create(:role, permissions: Permissions.defaults_for(:agent))) }

  def auth(user) = {"Authorization" => "Bearer #{user.api_token.token}"}
  def json = JSON.parse(response.body)

  before do
    Setting.set("updates", {"latest_version" => "99.0.0", "release_url" => "https://example.com/r", "notes" => "Faster pages.",
      "published_at" => "2026-09-30T12:00:00Z", "checked_at" => "2026-10-01T04:00:00Z"})
  end

  it "shows the version, the newest release and past updates to the Agent role" do
    Upgrade.create!(requested_by: admin, from_version: "0.0.1", to_version: "0.0.2", via: "local", status: "failed", message: "exit 1")

    with_env("CMS_UPDATES" => "manual") { get "/api/updates", headers: auth(agent) }

    expect(response).to have_http_status(:ok)
    updates = json["updates"]
    expect(updates).to include("version" => Cms::VERSION, "update_available" => true, "updates_by" => "manual",
      "not_set_up_because" => "Updating from here isn't set up on this install.", "daily_check" => true)
    expect(updates["latest_release"]).to include("version" => "99.0.0", "url" => "https://example.com/r", "notes" => "Faster pages.")
    expect(updates["past_updates"].sole).to include("from_version" => "0.0.1", "status" => "failed", "message" => "exit 1",
      "requested_by" => admin.name)
  end

  it "says it in one line in the agent envelope" do
    with_env("CMS_UPDATES" => "manual") { get "/api/updates", headers: auth(agent).merge("X-Agent-Envelope" => "1") }

    expect(json["summary"]).to eq("CMS #{Cms::VERSION}; 99.0.0 is out, and updating from the admin isn't set up.")
    expect(json["breadcrumbs"].map { it["command"] }).to eq(["cms updates check"])
  end

  it "checks GitHub now" do
    release = Net::HTTPOK.new("1.1", "200", "OK")
    allow(release).to receive(:body).and_return(JSON.generate(tag_name: "v#{Cms::VERSION}", html_url: "https://example.com/now"))
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil, request: release)
    allow(Net::HTTP).to receive(:new).and_return(http)

    post "/api/updates/check", headers: auth(agent)

    expect(response).to have_http_status(:ok)
    expect(json["updates"]).to include("update_available" => false)
    expect(json["updates"]["latest_release"]).to include("version" => Cms::VERSION, "url" => "https://example.com/now")
  end

  it "says why GitHub couldn't be asked" do
    allow(Net::HTTP).to receive(:new).and_raise(SocketError, "offline")

    post "/api/updates/check", headers: auth(agent)

    expect(response).to have_http_status(:bad_gateway)
    expect(json).to eq("error" => "github_unavailable", "message" => "Couldn't reach GitHub (offline).")
  end

  it "needs settings:read" do
    reader = create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))

    get "/api/updates", headers: auth(reader)

    expect(response).to have_http_status(:forbidden)
    expect(json).to include("capability" => "settings:read")
  end

  it "has no way to start an update, even for an admin's token" do
    with_env("CMS_UPDATES" => "local") { post "/api/updates", headers: auth(admin) }

    expect(response).to have_http_status(:not_found)
    expect(Upgrade.count).to eq(0)
  end
end
