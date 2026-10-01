# frozen_string_literal: true

require "rails_helper"

# The question this answers is not "is this recommendation good" — every other
# view already asks that. It is "was this cycle worth running", which only the
# set can answer.
RSpec.describe Agents::CycleSynthesis do
  let(:swarm) { Swarm.create!(name: "SEO", enabled: true) }
  let(:page) { Page.create!(title: "Pricing", slug: "pricing", status: "published") }

  def seat(name, frequency: "weekly", day: 1)
    agent = Agent.create!(name: name, instructions: "Work.", capability_keys: %w[read_pages])
    swarm.swarm_members.create!(agent: agent, frequency: frequency, day: day, hour: 9)
    agent
  end

  def run_for(agent, status: "completed", tokens: nil)
    AgentRun.create!(agent: agent, agent_name: agent.name, swarm: swarm, status: status,
      input_tokens: tokens&.first, output_tokens: tokens&.last,
      brief: {"agent" => {"preferred_model" => "glm-5.3"}})
  end

  def finding(run, kind: "metadata", subject: page, title: "Title is too long", status: "open")
    Recommendation.create!(agent_run: run, kind: kind, subject: subject, title: title, status: status)
  end

  it "says so plainly when nothing ran" do
    expect(described_class.new(swarm).to_h[:verdict]).to eq("No runs this cycle.")
  end

  # A clean cycle and a misaimed one produce the same number, so the sentence
  # has to name both possibilities rather than congratulating the rota.
  it "does not call an empty cycle a success" do
    run_for(seat("Metadata"))

    expect(described_class.new(swarm).to_h[:verdict])
      .to eq("1 runs, nothing filed. Either the site is clean or the rota is looking in the wrong place.")
  end

  it "counts the same finding from two seats as one piece of work duplicated" do
    finding(run_for(seat("Metadata")))
    finding(run_for(seat("Technical", day: 3)))

    result = described_class.new(swarm).to_h

    expect(result[:filed]).to eq(2)
    expect(result[:subjects]).to eq(1)
    expect(result[:duplicate_count]).to eq(1)
    expect(result[:overlap].first[:agents]).to contain_exactly("Metadata", "Technical")
    expect(result[:verdict]).to include("1 duplicated between seats")
  end

  # Two content gaps are two real gaps. Collapsing them because neither names
  # a page would erase the cycle's actual output.
  it "does not treat subjectless findings as duplicates of each other" do
    run = run_for(seat("Content"))
    finding(run, kind: "content_gap", subject: nil, title: "No page for “pricing vs”")
    finding(run, kind: "content_gap", subject: nil, title: "No page for “alternatives”")

    result = described_class.new(swarm).to_h

    expect(result[:duplicate_count]).to eq(0)
    expect(result[:subjects]).to eq(2)
  end

  it "prices the cycle from what its runs actually spent" do
    finding(run_for(seat("Metadata"), tokens: [1_000_000, 0]))

    expect(described_class.new(swarm).to_h[:cost]).to eq("$1.40")
  end

  it "counts a failed run against the cycle" do
    run_for(seat("Metadata"), status: "failed")
    finding(run_for(seat("Technical", day: 3)))

    result = described_class.new(swarm).to_h

    expect(result[:failed]).to eq(1)
    expect(result[:verdict]).to include("1 runs failed")
  end
end
