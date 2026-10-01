# frozen_string_literal: true

require "rails_helper"

# The one door to a model. What these pin is the shape of the boundary: the
# site's saved key is what switches it on, the context that reaches RubyLLM
# carries that key and Zen's base URL and nothing global, and a tier resolves
# to a model that actually exists.
#
# The global-config assertion keeps the key where Settings → AI put it: a key
# written into RubyLLM's global config would outlive a change or removal there.
RSpec.describe Ai::Zen do
  ZEN_SUBDOMAIN = "zenspec"


  before do
    SiteSetup.new(
      name: "Zen Spec",
      owner_email: "owner@#{ZEN_SUBDOMAIN}.example.com"
    ).call
    Setting.delete_key("ai")
  end

  describe "being configured" do
    it "is off until a key is saved, and on once one is" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENCODE_ZEN_API_KEY").and_return(nil)
      expect(described_class).not_to be_configured

      Setting.set_secret("ai", opencode_zen_api_key: "zen-key")
      expect(described_class).to be_configured
    end

    # The credential is a credential: a database file, a backup, or a stray
    # SELECT should not hand anyone a working key.
    it "keeps the key out of the plain settings data" do
      Setting.set_secret("ai", opencode_zen_api_key: "zen-key")
      Setting.set("ai", default_tier: "strong")

      expect(Setting.get("ai")).not_to have_key("opencode_zen_api_key")
      expect(described_class.api_key).to eq("zen-key")
    end

    it "refuses to build a context rather than calling on nothing" do
      allow(described_class).to receive(:api_key).and_return(nil)
      expect { described_class.context }.to raise_error(Ai::Zen::NotConfigured, /Settings → AI/)
    end
  end

  describe "the context it hands RubyLLM" do
    # Zen's base URL is the provider's own default (RubyLLM::Providers::Zen),
    # so all the context has to carry is the key; see zen_provider_spec.rb.
    it "carries this site's key, and leaves the global config alone" do
      Setting.set_secret("ai", opencode_zen_api_key: "zen-key")
      config = described_class.context.config

      expect(config.zen_api_key).to eq("zen-key")
      expect(RubyLLM.config.zen_api_key).to be_nil,
        "a global key outlives the one saved in Settings → AI"
      expect(RubyLLM.config.openai_api_key).to be_nil
    end
  end

  describe "tiers" do
    it "names what the work needs, and resolves to a model that exists" do
      expect(Ai::Models.resolve("cheap")).to eq("deepseek-v4-flash")
      expect(Ai::Models.resolve("strong")).to eq("kimi-k3")
      expect(Ai::Models.all).to have_key(Ai::Models.resolve("mid"))
    end

    it "keeps a stored model id runnable rather than dropping it" do
      expect(Ai::Models.resolve("glm-5.3")).to eq("glm-5.3")
      expect(Ai::Models.tier_of("glm-5.3")).to eq("mid")
    end

    it "degrades a model that no longer exists to the site's default tier" do
      Setting.set("ai", default_tier: "strong")
      expect(Ai::Models.resolve("opus")).to eq(Ai::Models.for_tier("strong"))
      expect(Ai::Models.resolve(nil)).to eq(Ai::Models.for_tier("strong"))
    end

    it "offers a stored id alongside the tiers instead of silently losing it" do
      labels = Ai::Models.options_including("glm-5.3").map { |o| o[:value] }
      expect(labels).to include("glm-5.3")
      expect(Ai::Models.options_including("mid").map { |o| o[:value] }).to eq(Ai::Models::TIERS)
    end

    it "runs an extra id typed into Settings" do
      Setting.set("ai", extra_model: "deepseek-v4-pro")
      expect(Ai::Models).to be_known("deepseek-v4-pro")
      expect(Ai::Models.resolve("deepseek-v4-pro")).to eq("deepseek-v4-pro")
    end
  end

  describe Ai::Oneshot do
    it "is absent rather than broken when no key is set" do
      allow(Ai::Zen).to receive(:configured?).and_return(false)
      expect(Ai::Oneshot.call(purpose: "spec", prompt: "hi")).to be_nil
    end

    it "asks on the cheap tier and takes the JSON out of a prose-wrapped answer" do
      Setting.set_secret("ai", opencode_zen_api_key: "zen-key")
      allow(Ai::Zen).to receive(:ask).and_return(%(Sure, here you go: {"ok": true}))

      expect(Ai::Oneshot.call(purpose: "spec", prompt: "hi", schema: {type: "object"}))
        .to eq({"ok" => true})
      expect(Ai::Zen).to have_received(:ask)
        .with("hi", model: "cheap", instructions: a_string_matching(/JSON schema/))
    end

    it "fails open when the model errors — a helper must never take a screen down" do
      Setting.set_secret("ai", opencode_zen_api_key: "zen-key")
      allow(Ai::Zen).to receive(:ask).and_raise("provider exploded")

      expect(Ai::Oneshot.call(purpose: "spec", prompt: "hi")).to be_nil
    end
  end
end
