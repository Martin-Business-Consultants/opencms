# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setting do
  describe ".get / .set" do
    it "returns {} for an unknown key" do
      expect(described_class.get("never-set")).to eq({})
    end

    it "round-trips a hash" do
      described_class.set("api", provider: "anthropic", default_model: "claude-sonnet-4-6")
      expect(described_class.get("api")).to eq("provider" => "anthropic", "default_model" => "claude-sonnet-4-6")
    end

    it "deep-merges on subsequent sets" do
      described_class.set("api", provider: "anthropic")
      described_class.set("api", default_model: "claude-haiku-4-5")
      expect(described_class.get("api")).to include("provider" => "anthropic", "default_model" => "claude-haiku-4-5")
    end
  end

  describe ".delete_key" do
    it "removes the row" do
      described_class.set("scratch", a: 1)
      expect(described_class.delete_key("scratch")).to eq(1)
      expect(described_class.get("scratch")).to eq({})
    end
  end
end
