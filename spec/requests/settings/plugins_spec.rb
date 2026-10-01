# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings › Plugins", type: :request do
  let(:admin) { create(:user) }

  after { forget_plugin(:future) }

  it "lists the installed plugins with their state" do
    sign_in_as admin

    get settings_plugins_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Hello", "bundled", "Switch on", "CMS #{Cms::VERSION}")
  end

  it "switches a plugin on and off, and audits it" do
    sign_in_as admin

    post settings_plugin_activation_path("hello")
    expect(response).to redirect_to(settings_plugins_path)
    expect(Cms::Plugins.enabled?(:hello)).to be(true)
    expect(AuditLog.last.action).to eq("plugin.enabled")

    delete settings_plugin_activation_path("hello")
    Current.plugin_states = nil
    expect(Cms::Plugins.enabled?(:hello)).to be(false)
    expect(AuditLog.last.action).to eq("plugin.disabled")
  end

  it "gives the built-in roles a plugin's standard permissions the first time it's switched on" do
    editor = Role.find_or_initialize_by(name: "Editor").tap { it.update!(permissions: %w[pages:read]) }
    sign_in_as admin

    post settings_plugin_activation_path("commerce")

    expect(flash[:notice]).to eq("Commerce is on. Editor got its standard permissions.")
    expect(editor.reload.permissions).to include("quotes:read", "invoices:send")
    expect(AuditLog.last).to have_attributes(action: "plugin.permissions_granted")
    expect(AuditLog.last.metadata["roles"]).to include("Editor")
  end

  it "won't switch on a plugin this version can't run" do
    Cms::Plugins.register :future, name: "Future", version: "9.0.0", description: "Later.", requires: ">= 99"
    sign_in_as admin

    post settings_plugin_activation_path("future")

    expect(flash[:alert]).to match(/needs CMS >= 99/)
    expect(Setting.get("plugins")).not_to have_key("future")
  end

  it "shows what a plugin adds" do
    sign_in_as admin

    get settings_plugin_path("hello")

    expect(response.body).to include("Menu: Tools › Hello", "Submenu: Tools › Hello greetings", "API: /api/hello/greetings")
  end

  it "needs settings:write to switch" do
    sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[settings:read]))

    get settings_plugins_path
    expect(response.body).not_to include("Switch on")

    post settings_plugin_activation_path("hello")
    expect(Cms::Plugins.enabled?(:hello)).to be(false)
  end

  it "is 404 for a plugin that isn't installed" do
    sign_in_as admin

    get settings_plugin_path("nope")

    expect(response).to have_http_status(:not_found)
  end
end
