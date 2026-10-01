# frozen_string_literal: true

require "rails_helper"

# A ticker that moves when nothing happened is worse than no ticker.
RSpec.describe Agents::Spend do
  let(:agent) { Agent.create!(name: "Metadata", instructions: "Fix titles.", capability_keys: %w[read_pages]) }

  def run(model:, input: 1_000_000, output: 0, created_at: Time.current)
    AgentRun.create!(agent: agent, agent_name: agent.name, status: "completed",
      input_tokens: input, output_tokens: output, created_at: created_at,
      brief: {"agent" => {"preferred_model" => model}})
  end

  before { Rails.cache.clear }

  it "prices a run at the model stamped in its own brief, not today's tier" do
    run(model: "glm-5.3")
    agent.update!(preferred_model: "strong")

    expect(described_class.new.compute[:window]).to eq("$1.40")
  end

  it "separates today from the window" do
    run(model: "glm-5.3")
    run(model: "glm-5.3", created_at: 10.days.ago)

    result = described_class.new.compute

    expect(result[:today]).to eq("$1.40")
    expect(result[:window]).to eq("$2.80")
    expect(result[:runs]).to eq(2)
  end

  it "ignores a run older than the window" do
    run(model: "glm-5.3", created_at: 40.days.ago)

    expect(described_class.new.compute[:runs]).to eq(0)
  end

  # A run whose brief names a model we don't have a rate for is counted as a
  # run and priced at zero, rather than dropped: "we ran something we can't
  # price" is a different fact from "we didn't run anything".
  it "counts an unpriceable run without inventing a number for it" do
    run(model: "some-model-we-never-shipped")

    result = described_class.new.compute

    expect(result[:runs]).to eq(1)
    expect(result[:window_cents]).to eq(0)
  end
end
