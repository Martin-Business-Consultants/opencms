# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marketing.hand_off" do
  it "says so when there is no Agents plugin to hand work to" do
    allow(Cms::Plugins).to receive(:provided).with(:agents).and_return(nil)

    expect(Marketing.hand_off("technical_seo")).to eq(:no_agents)
  end

  it "says so when the template doesn't exist" do
    allow(Cms::Plugins).to receive(:provided).with(:agents).and_return(double(hand_off: nil))

    expect(Marketing.hand_off("nope")).to eq(:unknown_template)
  end

  it "queues a run and records it as a hand-off" do
    run = double(agent_name: "Technical SEO Sweep")
    allow(Cms::Plugins).to receive(:provided).with(:agents).and_return(double(hand_off: run))
    expect(run).to receive(:track_event).with(:queued, agent: "Technical SEO Sweep", trigger: "hand_off", finding_id: "7")

    expect(Marketing.hand_off("technical_seo", finding_id: "7")).to eq(run)
  end
end
