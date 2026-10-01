# frozen_string_literal: true

require "rails_helper"

# The banner, the tiles and the sheet all read from this one object, so what
# it is asked to get right is the *ordering*: which of several true statements
# is the one to lead with.
RSpec.describe Agents::RosterState do
  def state(agents:, worker: healthy, latest: {})
    described_class.new(agents: agents, worker: worker, latest: latest)
  end

  let(:healthy) { {seen_recently: true, queued: 0, active: 0} }
  let(:dark) { {seen_recently: false, queued: 3, active: 0} }

  def build_agent(name: "Metadata", **attrs)
    Agent.create!({name: name, instructions: "Fix titles.", capability_keys: %w[read_pages],
                   enabled: true, last_run_at: 1.hour.ago}.merge(attrs))
  end

  def build_run(agent, status:, summary: nil)
    AgentRun.create!(agent: agent, agent_name: agent.name, status: status, summary: summary)
  end

  let(:agent) { build_agent }

  it "leads with a missing harness even when everything else looks fine" do
    result = state(agents: [agent], worker: dark)

    expect(result.severity).to eq("danger")
    expect(result.headline).to eq("No harness has claimed work recently")
    expect(result.detail).to include("3 runs queued")
  end

  it "leads with a failure when the harness is alive" do
    run = build_run(agent, status: "failed", summary: "cms pages list exited 1")
    result = state(agents: [agent], latest: {agent.id => run})

    expect(result.severity).to eq("danger")
    expect(result.headline).to eq("1 agent failed on the last run")
    expect(result.items.first.detail).to eq("cms pages list exited 1")
  end

  it "says nothing needs a person when nothing does" do
    run = build_run(agent, status: "completed")
    result = state(agents: [agent], latest: {agent.id => run})

    expect(result.severity).to eq("success")
    expect(result.headline).to eq("1 agent running on schedule")
    expect(result.attention_count).to eq(0)
  end

  # An available upgrade is worth showing and is never a reason to interrupt
  # someone: it is information, not a fault, and it must not colour the tile.
  it "keeps a library upgrade out of the attention count" do
    allow(agent).to receive_messages(upgradable?: true, template_version: 1, latest_template_version: 2)
    run = build_run(agent, status: "completed")
    result = state(agents: [agent], latest: {agent.id => run})

    expect(result.items.map(&:severity)).to eq(["info"])
    expect(result.attention_count).to eq(0)
    expect(result.severity).to eq("info")
    expect(result.headline).to eq("1 agent has a newer library version")
  end

  it "counts an enabled agent that has never run as needing a person" do
    never = build_agent(name: "Never", last_run_at: nil)
    result = state(agents: [never])

    expect(result.attention_count).to eq(1)
    expect(result.items.first.title).to include("has never run")
  end
end
