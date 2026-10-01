# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings: the version and updates", type: :request do
  let(:admin) { create(:user) }
  let(:editor) { create(:user, admin: false, role: create(:role, permissions: Permissions.defaults_for(:editor))) }
  let(:writer) { create(:user, admin: false, role: create(:role, permissions: %w[settings:read settings:write])) }

  def newer_release_out
    Setting.set("updates", {"latest_version" => "99.0.0", "release_url" => "https://example.com/r",
      "notes" => "Faster pages.", "published_at" => "2026-09-30T12:00:00Z", "checked_at" => 1.hour.ago.iso8601})
  end

  def github_answers(response)
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request).and_return(response)
  end

  def release_response(tag)
    Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
      allow(response).to receive(:body).and_return(JSON.generate(tag_name: tag, html_url: "https://example.com/#{tag}"))
    end
  end

  describe "the Settings index" do
    before { sign_in_as admin }

    it "shows the version" do
      get settings_path

      expect(response.body).to include("CMS #{Cms::VERSION}")
      expect(response.body).not_to include("is available")
    end

    it "says when a newer release is out, and points to Settings › Updates" do
      newer_release_out

      get settings_path

      expect(response.body).to include("Version 99.0.0 is available", "https://example.com/r", settings_updates_path)
      expect(response.body).not_to include("bin/update v99.0.0")
    end
  end

  describe "the page" do
    it "lists Updates under Workspace, and the admin bar's notice leads to it" do
      newer_release_out
      sign_in_as admin

      get settings_updates_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Updates", "CMS 99.0.0", "Faster pages.", "cms updates")
      expect(response.body).to match(%r{href="/settings/updates"[^>]*admin-bar__update|admin-bar__update[^>]*href="/settings/updates"})
    end

    it "shows the command to run when updating from here isn't set up" do
      newer_release_out
      sign_in_as admin

      with_env("CMS_UPDATES" => "manual") { get settings_updates_path }

      expect(response.body).to include("isn&#39;t set up", "bin/update v99.0.0")
      expect(response.body).not_to include("Update now")
    end

    it "offers the update to an admin when it's set up" do
      newer_release_out
      sign_in_as admin

      with_env("CMS_UPDATES" => "local") { get settings_updates_path }

      expect(response.body).to include("Update to 99.0.0", "Update now")
    end

    it "shows an editor the version but no button" do
      newer_release_out
      sign_in_as editor

      with_env("CMS_UPDATES" => "local") { get settings_updates_path }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("An admin can update to it from here.")
      expect(response.body).not_to include("Update now")
    end

    it "keeps out a role without settings:read" do
      sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))

      get settings_updates_path

      expect(response).to have_http_status(:redirect)
    end

    it "follows a running update, and settles it once this version is running" do
      Upgrade.create!(requested_by: admin, from_version: "0.1.0", to_version: "99.0.0", via: "local")
      Upgrade.create!(requested_by: admin, from_version: "0.0.1", to_version: Cms::VERSION, via: "local", created_at: 1.day.ago)
      sign_in_as admin

      get settings_updates_path

      expect(response.body).to include("Updating to 99.0.0", 'data-controller="refresh"')
      expect(Upgrade.order(:id).pluck(:status)).to eq(%w[running succeeded])
    end
  end

  describe "updating" do
    around { |example| with_env("CMS_UPDATES" => "local") { example.run } }
    before { newer_release_out }

    it "starts the update for an admin" do
      expect_any_instance_of(Upgrade::Local).to receive(:start)
      sign_in_as admin

      post settings_updates_path

      expect(response).to redirect_to(settings_updates_path)
      expect(flash[:notice]).to start_with("Updating to 99.0.0.")
      expect(Upgrade.sole).to have_attributes(requested_by: admin, to_version: "99.0.0", status: "running")
    end

    it "says why it didn't start" do
      Upgrade.create!(requested_by: admin, from_version: Cms::VERSION, to_version: "99.0.0", via: "local")
      sign_in_as admin

      post settings_updates_path

      expect(flash[:alert]).to match(/already running/)
    end

    it "refuses anyone who isn't an admin, even with settings:write" do
      [editor, writer].each do |person|
        sign_in_as person

        post settings_updates_path

        expect(flash[:alert]).to match(/permission/)
      end
      expect(Upgrade.count).to eq(0)
    end
  end

  describe "Check now" do
    it "asks GitHub and says what it found" do
      github_answers(release_response("v99.0.0"))
      sign_in_as editor

      post settings_updates_check_path

      expect(response).to redirect_to(settings_updates_path)
      expect(flash[:notice]).to eq("CMS 99.0.0 is out. This install runs #{Cms::VERSION}.")
    end

    it "says this is the newest" do
      github_answers(release_response("v#{Cms::VERSION}"))
      sign_in_as admin

      post settings_updates_check_path

      expect(flash[:notice]).to eq("CMS #{Cms::VERSION} is the newest release.")
    end

    it "says why GitHub couldn't be asked" do
      allow(Net::HTTP).to receive(:new).and_raise(SocketError, "offline")
      sign_in_as admin

      post settings_updates_check_path

      expect(flash[:alert]).to eq("Couldn't reach GitHub (offline).")
    end
  end
end
