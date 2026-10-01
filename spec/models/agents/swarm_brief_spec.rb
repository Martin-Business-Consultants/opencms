# frozen_string_literal: true

require "rails_helper"

# A swarm's characteristic failure is five agents each doing their job well
# and filing the same finding five times. These are the two facts that stop
# it, and both have to be in the brief before the model starts.
RSpec.describe Agents::SwarmBrief do
  let(:swarm) { Swarm.create!(name: "SEO", enabled: true) }
  let(:page) { Page.create!(title: "Pricing", slug: "pricing", status: "published") }

  def seat(name, frequency: "weekly")
    agent = Agent.create!(name: name, instructions: "Work.", capability_keys: %w[read_pages])
    swarm.swarm_members.create!(agent: agent, frequency: frequency, day: 1, hour: 9)
    agent
  end

  def run_for(agent, created_at: Time.current)
    AgentRun.create!(agent: agent, agent_name: agent.name, swarm: swarm, status: "completed",
      created_at: created_at)
  end

  it "tells a later seat what earlier seats already filed this cycle" do
    agent = seat("Metadata")
    Recommendation.create!(agent_run: run_for(agent), kind: "metadata", subject: page,
      title: "Title is too long")

    filed = described_class.new(swarm).to_h[:already_filed]

    expect(filed.first).to include(kind: "metadata", title: "Title is too long", by: "Metadata")
  end

  # The reason is the useful half. "We're deliberately not targeting that
  # query" is something the next run can act on; a bare "dismissed" only tells
  # it to be quiet.
  it "carries dismissals with the reason a person gave" do
    agent = seat("Content")
    Recommendation.create!(agent_run: run_for(agent), kind: "content_gap", title: "Write a comparison page",
      status: "dismissed", decision_comment: "We don't compete on that query.")

    settled = described_class.new(swarm).to_h[:settled]

    expect(settled.first).to include(title: "Write a comparison page", reason: "We don't compete on that query.")
  end

  it "leaves an accepted finding out of the settled list" do
    agent = seat("Metadata")
    Recommendation.create!(agent_run: run_for(agent), kind: "metadata", subject: page,
      title: "Title is too long", status: "accepted")

    expect(described_class.new(swarm).to_h[:settled]).to be_empty
  end

  # The cycle is the current pass of the rota, taken from the slowest seat.
  # A weekly swarm shown a fortnight of findings would tell every agent that
  # last week's work is already covered.
  it "takes the cycle length from the slowest seat" do
    seat("Nightly", frequency: "daily")
    seat("Monthly", frequency: "monthly")

    result = described_class.new(swarm).to_h

    expect(result[:cycle][:length]).to eq("monthly")
  end

  it "keeps a finding from a previous cycle out of already_filed" do
    agent = seat("Metadata", frequency: "daily")
    old = run_for(agent, created_at: 3.days.ago)
    Recommendation.create!(agent_run: old, kind: "metadata", subject: page, title: "Old news")

    expect(described_class.new(swarm).to_h[:already_filed]).to be_empty
  end
end
