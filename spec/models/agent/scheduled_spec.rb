# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::Scheduled do
  let!(:agent) do
    Agent.create!(
      name: "Nightly", instructions: "Sweep.", capability_keys: %w[read_pages],
      cron: "0 6 * * *", enabled: true
    )
  end

  def dispatch(now) = Agent.dispatch_due(now)

  it "queues nothing before the cron is due" do
    expect { dispatch(Time.current) }.not_to change { AgentRun.count }
  end

  it "queues a run once the cron time arrives" do
    travel_to(agent.next_due_at + 1.minute) do
      expect { dispatch(Time.current) }.to change { AgentRun.count }.by(1)
      expect(AgentRun.last.trigger).to eq("schedule")
    end
  end

  it "advances the cadence so it doesn't fire twice in one window" do
    travel_to(agent.next_due_at + 1.minute) do
      dispatch(Time.current)

      expect { dispatch(Time.current) }.not_to change { AgentRun.count }
    end
  end

  # A worker that is slow or absent shouldn't produce a backlog of identical
  # work that all lands at once when it comes back.
  it "skips an agent whose last run is still in flight" do
    agent.dispatch!
    agent.update!(next_due_at: 1.minute.ago)

    expect { dispatch(Time.current) }.not_to change { AgentRun.count }
  end

  it "queues again once the previous run has finished" do
    run = agent.dispatch!
    run.update!(status: "completed", finished_at: Time.current)
    agent.update!(next_due_at: 1.minute.ago)

    expect { dispatch(Time.current) }.to change { AgentRun.count }.by(1)
  end

  it "ignores a disabled agent" do
    agent.update!(enabled: false)

    expect { dispatch(Time.current) }.not_to change { AgentRun.count }
  end
end
