# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentRun do
  let(:agent) do
    Agent.create!(name: "Sweep", instructions: "Look around.", capability_keys: %w[read_pages])
  end

  def queue(**attrs) = agent.dispatch!(**attrs)

  describe ".claim!" do
    it "hands out a queued run and stamps the lease" do
      run = queue

      claimed = described_class.claim!(worker: "box-1")

      expect(claimed.id).to eq(run.id)
      expect(claimed).to be_claimed
      expect(claimed.claimed_by).to eq("box-1")
      expect(claimed.attempts).to eq(1)
      expect(claimed.lease_expires_at).to be > Time.current
    end

    it "returns nil when nothing is queued" do
      expect(described_class.claim!(worker: "box-1")).to be_nil
    end

    # Two workers polling at the same moment must not both get the same run:
    # it would be executed twice and write to the site twice.
    it "never hands the same run to two workers" do
      queue

      first  = described_class.claim!(worker: "box-1")
      second = described_class.claim!(worker: "box-2")

      expect(first).to be_present
      expect(second).to be_nil
    end

    it "prefers higher priority, then older" do
      old_normal = queue(priority: 0)
      old_normal.update!(created_at: 1.hour.ago)
      urgent = queue(priority: 1)

      expect(described_class.claim!(worker: "box-1").id).to eq(urgent.id)
    end

    it "skips runs that have already expired" do
      queue.update!(expires_at: 1.minute.ago)

      expect(described_class.claim!(worker: "box-1")).to be_nil
    end
  end

  describe "lifecycle" do
    it "moves claimed → running → completed" do
      queue
      run = described_class.claim!(worker: "box-1")

      expect(run.start!).to be(true)
      expect(run).to be_running
      expect(run.complete!(summary: "Did the thing")).to be(true)
      expect(run).to be_completed
      expect(run.summary).to eq("Did the thing")
      expect(agent.reload.last_run_at).to be_present
    end

    it "refuses to complete a run that is no longer the worker's" do
      queue
      run = described_class.claim!(worker: "box-1")
      run.start!
      run.complete!(summary: "first")

      expect(run.complete!(summary: "second")).to be(false)
      expect(run.reload.summary).to eq("first")
    end

    it "appends transcript steps only while active" do
      queue
      run = described_class.claim!(worker: "box-1")

      expect(run.report!(message: "reading pages")).to be_truthy
      expect(run.transcript.last["message"]).to eq("reading pages")

      run.start!
      run.complete!(summary: "done")
      expect(run.report!(message: "too late")).to be(false)
    end
  end

  describe "#heartbeat!" do
    it "extends the lease without changing status" do
      queue
      run = described_class.claim!(worker: "box-1")
      run.start!
      was = run.lease_expires_at

      travel_to(2.minutes.from_now) do
        expect(run.heartbeat!).to be(true)
        expect(run.reload.lease_expires_at).to be > was
        expect(run).to be_running
      end
    end

    # This is the signal that tells a worker to stop rather than keep
    # burning tokens on work that has been requeued.
    it "returns false once the run is no longer active" do
      queue
      run = described_class.claim!(worker: "box-1")
      run.start!
      run.fail!(error: "boom")

      expect(run.heartbeat!).to be(false)
    end
  end

  describe ".reap!" do
    # The rule this design exists for: a queued run with no worker is
    # WAITING, not stale. Reaping it would fail work nobody has attempted.
    it "leaves queued runs alone however old" do
      run = queue
      run.update!(created_at: 3.days.ago)

      expect { described_class.reap! }.not_to change { run.reload.status }
    end

    it "requeues a claimed run whose lease lapsed" do
      queue
      run = described_class.claim!(worker: "box-1")
      run.update!(lease_expires_at: 1.minute.ago)

      expect(described_class.reap!).to include(requeued: 1)
      expect(run.reload).to be_queued
      expect(run.claimed_by).to be_nil
      expect(run.attempts).to eq(1)
    end

    it "fails a run that keeps losing its lease" do
      queue
      run = nil
      described_class::MAX_ATTEMPTS.times do
        run = described_class.claim!(worker: "box-1")
        run.update!(lease_expires_at: 1.minute.ago)
        described_class.reap!
      end

      expect(run.reload).to be_failed
      expect(run.error).to include("Abandoned")
    end

    it "expires a run nobody claimed in time" do
      run = queue
      run.update!(expires_at: 1.minute.ago)

      expect(described_class.reap!).to include(expired: 1)
      expect(run.reload).to be_expired
    end
  end

  describe "#request_cancel!" do
    it "kills a queued run outright" do
      run = queue
      run.request_cancel!

      expect(run.reload).to be_canceled
    end

    it "flags a running run, then forces it down on a second request" do
      queue
      run = described_class.claim!(worker: "box-1")
      run.start!

      run.request_cancel!
      expect(run.reload).to be_running
      expect(run).to be_stopping

      run.request_cancel!
      expect(run.reload).to be_canceled
    end
  end
end
