# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::ConnectionTest do
  let(:profile) { Reports::Profile.new({}, {}) }

  it "says who it's connected as and what the balance is" do
    client = double(ping: {login: "acme", balance: 12.5})

    outcome = described_class.new(client: client, profile: profile).run

    expect(outcome).to be_ok
    expect(outcome.message).to start_with("Connected as acme. Balance $12.50.")
    expect(outcome.message).to include("No location set yet")
  end

  it "is not OK with an empty balance" do
    outcome = described_class.new(client: double(ping: {login: "acme", balance: 0}), profile: profile).run

    expect(outcome).not_to be_ok
    expect(outcome.message).to match(/balance is \$0.00/)
  end

  it "answers with the API's message when the credential fails, the client's construction included" do
    allow(DataForSeo::Client).to receive(:from_settings).and_raise(DataForSeo::Error.new("bad login"))

    outcome = described_class.new(profile: profile).run

    expect(outcome).not_to be_ok
    expect(outcome.message).to eq("bad login")
  end
end
