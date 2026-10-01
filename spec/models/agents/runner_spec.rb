# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Runner do
  let(:agent) do
    Agent.create!(name: "Sweeper", instructions: "Audit the site.",
      capability_keys: %w[manifest read_pages search write_pages recommend])
  end

  def fake_llm(reply: "All done.")
    llm = double("llm")
    allow(llm).to receive(:with_instructions).and_return(llm)
    allow(llm).to receive(:with_tools).and_return(llm)
    allow(llm).to receive(:before_tool_call).and_return(llm)
    allow(llm).to receive(:after_message).and_return(llm)
    allow(llm).to receive(:ask).and_return(double(content: reply))
    llm
  end

  describe ".perform" do
    it "claims the queued run, executes, and completes it with the reply as summary" do
      run = agent.dispatch!
      allow(Ai::Zen).to receive(:chat).and_return(fake_llm(reply: "Audited 12 pages."))

      result = described_class.perform(run)

      expect(result).to be_completed
      expect(result.summary).to eq("Audited 12 pages.")
      expect(result.claimed_by).to eq("in-process")
      expect(result.transcript.map { |s| s["kind"] }).to include("start")
    end

    it "returns nil when another worker already claimed the run" do
      run = agent.dispatch!
      AgentRun.claim!(worker: "box-1")

      expect(described_class.perform(run)).to be_nil
      expect(run.reload).to be_claimed
      expect(run.claimed_by).to eq("box-1")
    end

    it "requeues the run when the Zen key vanished between dispatch and execution" do
      run = agent.dispatch!
      allow(Ai::Zen).to receive(:chat).and_raise(Ai::Zen::NotConfigured)

      result = described_class.perform(run)

      expect(result).to be_queued
      expect(result.claimed_by).to be_nil
    end

    it "leaves a run canceled while queued exactly as it is" do
      run = agent.dispatch!
      run.request_cancel! # queued runs die immediately

      expect(described_class.perform(run)).to be_nil
      expect(run.reload).to be_canceled
    end

    it "records a failure with the error preserved" do
      run = agent.dispatch!
      allow(Ai::Zen).to receive(:chat).and_raise(RuntimeError, "boom")

      result = described_class.perform(run)

      expect(result).to be_failed
      expect(result.error).to include("boom")
    end
  end

  describe "instructions" do
    it "carries the agent's instructions, scope and budget into the system prompt" do
      run = agent.dispatch!
      text = described_class.instructions_for(run, run.brief.deep_stringify_keys)

      expect(text).to include("Audit the site.")
      expect(text).to include("BUDGET")
      expect(text).to include("site_manifest")
    end
  end
end
