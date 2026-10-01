# frozen_string_literal: true

require "rails_helper"

# The paths that could put a record live without the publish capability,
# found in the phase 2 audit: restoring a trashed live page, granting an agent
# a publish key, and a person's in-process run calling a publish tool.
RSpec.describe "Publish gate on the remaining paths", type: :request do
  let(:restorer) { create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write trash:read trash:write])) }
  let(:publisher) { create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write pages:publish trash:read trash:write])) }

  def trashed_live_page
    Page.create!(slug: "p-#{SecureRandom.hex(3)}", title: "Live", status: "published", published_at: Time.current).tap(&:discard!)
  end

  describe "restoring a trashed live page" do
    it "comes back as a draft for someone who can't publish, and says so" do
      page = trashed_live_page
      sign_in_as restorer

      post trash_item_restoration_url("page", page.id)

      expect(flash[:notice]).to match(/Restored as a draft/)
      expect(page.reload).to have_attributes(status: "draft", deleted_at: nil)
      expect(AuditLog.where(action: "trash.restored").last.metadata).to include("as_draft" => true)
    end

    it "comes back live for someone who can publish" do
      page = trashed_live_page
      sign_in_as publisher

      post trash_item_restoration_url("page", page.id)

      expect(page.reload).to have_attributes(status: "published", deleted_at: nil)
    end

    it "comes back as a draft through the API too" do
      page = trashed_live_page

      post "/api/trash/page/#{page.id}/restore", headers: {"Authorization" => "Bearer #{restorer.api_token.token}"}, as: :json

      expect(response).to have_http_status(:success)
      expect(page.reload.status).to eq("draft")
    end
  end

  describe "granting an agent a publish key" do
    it "needs the capability the key stands for" do
      agent = Agent.new(name: "Publisher", instructions: "Publish.", capability_keys: %w[read_pages publish_pages])
      agent.granted_by = restorer.role

      expect(agent).not_to be_valid
      expect(agent.errors[:capability_keys].join).to match(/pages:publish/)

      agent.granted_by = publisher.role
      expect(agent).to be_valid
    end

    it "lets someone without it keep an agent's existing key while editing it" do
      agent = Agent.create!(name: "Publisher", instructions: "Publish.", capability_keys: %w[read_pages publish_pages])
      agent.granted_by = restorer.role

      expect(agent.update(instructions: "Publish carefully.")).to be(true)
    end

    it "is refused from the admin form" do
      sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[agents:read agents:write pages:read pages:write]))
      switch_plugin(:ai, on: true)
      switch_plugin(:agents, on: true)

      expect {
        post agents_path, params: {agent: {name: "Sneaky", instructions: "Publish.", capability_keys: %w[read_pages publish_pages]}}
      }.not_to change(Agent, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "a person's run calling a publish tool" do
    let(:agent) { Agent.create!(name: "Publisher", instructions: "Publish.", capability_keys: %w[read_pages publish_pages]) }

    it "refuses when the person who started it can't publish" do
      page = Page.create!(slug: "draft-one", title: "Draft", status: "draft")
      run = agent.dispatch!(triggered_by: restorer)

      result = Agents::Tools::PublishPage.new(run).call("path" => page.path)

      expect(result).to include(error: "forbidden")
      expect(page.reload.status).to eq("draft")
    end

    it "publishes when they can" do
      page = Page.create!(slug: "draft-two", title: "Draft", status: "draft")
      run = agent.dispatch!(triggered_by: publisher)

      Agents::Tools::PublishPage.new(run).call("path" => page.path)

      expect(page.reload.status).to eq("published")
    end
  end
end
