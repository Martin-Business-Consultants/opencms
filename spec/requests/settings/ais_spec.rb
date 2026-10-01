# frozen_string_literal: true

require "rails_helper"

# The one screen in the CMS that handles a credential.
#
# What these examples pin is not "the form saves" — it is that the key goes
# somewhere the page can't leak it back out. A settings page that echoes the
# secret it just stored is the ordinary way a key ends up in a browser cache,
# a screenshot, or a support ticket.
RSpec.describe "Settings::AI", type: :request do
  let(:user) { create(:user, admin: true) }

  before do
    switch_plugin :ai, on: true
    sign_in_as(user)
  end

  it "shows whether a key is set without ever sending it" do
    Setting.set_secret("ai", opencode_zen_api_key: "sk-zen-abcdef123456")

    get "/settings/ai"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Already set · ends in 3456", "Test the key")
    expect(response.body).not_to include("sk-zen-abcdef123456")
  end

  it "stores the key in the encrypted column rather than the plain settings data" do
    patch "/settings/ai", params: {settings: {opencode_zen_api_key: "sk-zen-secret", default_tier: "strong"}}

    expect(Setting.secret("ai", :opencode_zen_api_key)).to eq("sk-zen-secret")
    expect(Setting.get("ai")).not_to have_key("opencode_zen_api_key")
    expect(Setting.get("ai")["default_tier"]).to eq("strong")
  end

  # A password field never receives its own value back, so an empty one means
  # "I didn't touch this" — not "delete my key".
  it "leaves a saved key alone when the field comes back blank" do
    Setting.set_secret("ai", opencode_zen_api_key: "sk-zen-keepme")

    patch "/settings/ai", params: {settings: {opencode_zen_api_key: "", default_tier: "cheap"}}

    expect(Setting.secret("ai", :opencode_zen_api_key)).to eq("sk-zen-keepme")
  end

  it "ignores a tier it doesn't ship" do
    patch "/settings/ai", params: {settings: {default_tier: "galaxy_brain"}}

    expect(Setting.get("ai")["default_tier"]).to be_nil
  end

  describe "testing the key" do
    it "asks for a key before making a call" do
      post "/settings/ai/test"

      expect(flash[:alert]).to eq("Add a key first.")
    end

    it "reports a real round trip" do
      Setting.set_secret("ai", opencode_zen_api_key: "sk-zen-live")
      allow(Ai::Zen).to receive(:ping).and_return(true)

      post "/settings/ai/test"

      expect(flash[:notice]).to include("OpenCode Zen answered")
    end

    # The failure a person actually hits is a network one, and it has to read
    # as "the test failed", never as a 500.
    it "turns a raised error into a message on the page" do
      Setting.set_secret("ai", opencode_zen_api_key: "sk-zen-live")
      allow(Ai::Zen).to receive(:ping).and_raise(StandardError, "connection refused")

      post "/settings/ai/test"

      expect(flash[:alert]).to include("connection refused")
    end
  end
end
