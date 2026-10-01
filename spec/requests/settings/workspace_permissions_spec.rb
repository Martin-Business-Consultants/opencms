# frozen_string_literal: true

require "rails_helper"

# The workspace's settings (General, Branding, Brand context, GitHub, Deploy,
# AI) take settings:read to open and settings:write to save. Your own
# account's pages stay open to anyone signed in.
RSpec.describe "Workspace settings permissions", type: :request do
  before { Session.delete_all }

  let(:editor) { create(:user, admin: false, role: create(:role, permissions: Permissions.defaults_for(:editor))) }
  let(:writer) { create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write])) }

  it "shows an editor (settings:read, not :write) the page with the form disabled" do
    sign_in_as editor

    get settings_general_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/<fieldset[^>]*disabled/)
  end

  it "refuses an editor's save and leaves the setting as it was" do
    sign_in_as editor

    patch settings_general_path, params: {settings: {title: "Renamed by an editor"}}

    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to match(/permission/)
    expect(Setting.get("general")["title"]).to be_nil
  end

  it "refuses a deploy trigger without settings:write" do
    sign_in_as editor

    post settings_deploy_trigger_path

    expect(flash[:alert]).to match(/permission/)
  end

  it "keeps a role without settings:read out of every workspace page" do
    sign_in_as writer

    %w[/settings/general /settings/branding /settings/brand /settings/github /settings/deploy].each do |path|
      get path
      expect(response).to have_http_status(:redirect), path
    end
  end

  it "keeps your own account's pages open to anyone signed in" do
    sign_in_as writer

    %w[/settings/profile /settings/password /settings/two_factor /settings/sessions /settings/api_token /settings/appearance].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
    end
  end

  it "lets an admin save" do
    sign_in_as create(:user)

    patch settings_general_path, params: {settings: {title: "Renamed"}}

    expect(Setting.get("general")["title"]).to eq("Renamed")
  end
end
