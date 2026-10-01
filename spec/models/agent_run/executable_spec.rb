# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentRun::Executable do
  include ActiveJob::TestHelper

  let(:agent) { Agent.create!(name: "Sweep", instructions: "Look.", capability_keys: %w[read_pages]) }

  it "queues the run for this process when the site holds a Zen key" do
    Setting.set_secret("ai", opencode_zen_api_key: "zen-key")

    expect { agent.dispatch!(trigger: "manual") }.to have_enqueued_job(AgentRun::ExecutionJob)
  end

  it "leaves the run for a worker box without one" do
    expect { agent.dispatch!(trigger: "manual") }.not_to have_enqueued_job(AgentRun::ExecutionJob)
  end

  it "runs only a queued run, and only while the key is there" do
    Setting.set_secret("ai", opencode_zen_api_key: "zen-key")
    run = agent.dispatch!(trigger: "manual")
    allow(Agents::Runner).to receive(:perform)

    run.execute_now
    expect(Agents::Runner).to have_received(:perform).with(run).once

    Setting.set_secret("ai", opencode_zen_api_key: nil)
    run.execute_now
    expect(Agents::Runner).to have_received(:perform).once
  end
end
