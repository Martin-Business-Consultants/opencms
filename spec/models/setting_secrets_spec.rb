# frozen_string_literal: true

require "rails_helper"

# Provider API keys used to sit in the plain `data` JSON column. They now live
# in `secrets`, encrypted at rest — a database file, backup, or stray query no
# longer hands someone a working key.
RSpec.describe "Setting secrets" do
  it "round-trips a secret" do
    Setting.set_secret("ai", api_key: "sk-live-abcdef")
    expect(Setting.secret("ai", :api_key)).to eq("sk-live-abcdef")
  end

  it "stores the ciphertext, not the key" do
    Setting.set_secret("ai", api_key: "sk-live-abcdef")

    raw = Setting.connection.select_value(
      Setting.sanitize_sql_array(["SELECT secrets FROM settings WHERE key = ?", "ai"])
    ).to_s

    expect(raw).not_to include("sk-live-abcdef")
    expect(raw).to be_present
  end

  it "keeps secrets out of the plain data column" do
    Setting.set("ai", provider: "anthropic")
    Setting.set_secret("ai", api_key: "sk-live-abcdef")

    expect(Setting.get("ai")).to eq("provider" => "anthropic")
    expect(Setting.get("ai")).not_to have_key("api_key")
  end

  it "merges rather than replacing other secrets" do
    Setting.set_secret("ai", api_key: "one")
    Setting.set_secret("ai", other_key: "two")

    expect(Setting.secret("ai", :api_key)).to eq("one")
    expect(Setting.secret("ai", :other_key)).to eq("two")
  end

  it "treats a blank value as a delete, not an empty string" do
    Setting.set_secret("ai", api_key: "one")
    Setting.set_secret("ai", api_key: "")

    expect(Setting.secret("ai", :api_key)).to be_nil
  end

  it "returns nil for a settings key that doesn't exist" do
    expect(Setting.secret("nope", :api_key)).to be_nil
  end

  it "does not disturb ordinary settings values" do
    Setting.set("ai", provider: "anthropic", default_model: "claude-sonnet-4-6")
    Setting.set_secret("ai", api_key: "sk-live")

    expect(Setting.get("ai")["default_model"]).to eq("claude-sonnet-4-6")
  end
end
