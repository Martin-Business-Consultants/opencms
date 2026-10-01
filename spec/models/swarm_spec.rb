# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarm do
  def make_agent(name)
    Agent.create!(name: name, instructions: "Work.", capability_keys: %w[read_pages])
  end

  let(:swarm) { Swarm.create!(name: "SEO", enabled: true) }

  describe SwarmMember do
    describe "#due?" do
      it "fires on the matching weekday and hour" do
        member = swarm.swarm_members.create!(
          agent: make_agent("Meta"), frequency: "weekly", day: 1, hour: 9
        )

        monday_9am = Time.zone.local(2026, 8, 24, 9, 30)
        expect(member.due?(monday_9am)).to be(true)
        expect(member.due?(monday_9am + 1.hour)).to be(false)
        expect(member.due?(monday_9am + 1.day)).to be(false)
      end

      # Ruby's wday is Sunday=0; an ISO day column makes Sunday 7. Getting
      # this wrong makes a Sunday seat silently never fire.
      it "treats Sunday as ISO day 7" do
        member = swarm.swarm_members.create!(
          agent: make_agent("Sunday"), frequency: "weekly", day: 7, hour: 6
        )

        expect(member.due?(Time.zone.local(2026, 8, 23, 6, 0))).to be(true)
      end

      it "fires once per slot, however often it is asked" do
        member = swarm.swarm_members.create!(
          agent: make_agent("Daily"), frequency: "daily", hour: 6
        )
        now = Time.zone.local(2026, 8, 24, 6, 0)

        expect(member.due?(now)).to be(true)
        member.mark_enqueued!(at: now)
        expect(member.due?(now + 20.minutes)).to be(false)
        expect(member.due?(now + 1.day)).to be(true)
      end

      it "is never due while disabled" do
        member = swarm.swarm_members.create!(
          agent: make_agent("Off"), frequency: "daily", hour: 9, enabled: false
        )

        expect(member.due?(Time.zone.local(2026, 8, 24, 9, 0))).to be(false)
      end
    end

    # Day 31 silently never fires in February.
    it "refuses a monthly seat past day 28" do
      member = swarm.swarm_members.build(agent: make_agent("Late"), frequency: "monthly", day: 31)

      expect(member).not_to be_valid
      expect(member.errors[:day].join).to include("1–28")
    end

    it "refuses the same agent twice in one swarm" do
      agent = make_agent("Dup")
      swarm.swarm_members.create!(agent: agent, frequency: "daily", hour: 9)
      duplicate = swarm.swarm_members.build(agent: agent, frequency: "daily", hour: 10)

      expect(duplicate).not_to be_valid
    end
  end

  describe "#dispatch_due!" do
    it "queues a run per due seat and advances that seat's rota" do
      member = swarm.swarm_members.create!(
        agent: make_agent("Meta"), frequency: "weekly", day: 1, hour: 9
      )
      monday = Time.zone.local(2026, 8, 24, 9, 0)

      runs = swarm.dispatch_due!(monday)

      expect(runs.size).to eq(1)
      expect(runs.first.trigger).to eq("swarm")
      expect(runs.first.swarm_member).to eq(member)
      expect(member.reload.last_enqueued_at).to be_present
      expect(swarm.dispatch_due!(monday)).to be_empty
    end

    # The swarm's own switch has to beat its members', or disabling a team
    # leaves its rota running.
    it "queues nothing while the swarm is disabled" do
      swarm.swarm_members.create!(agent: make_agent("Meta"), frequency: "daily", hour: 9)
      swarm.update!(enabled: false)

      expect(swarm.dispatch_due!(Time.zone.local(2026, 8, 24, 9, 0))).to be_empty
    end

    # Firing a seat must not satisfy the agent's own personal cadence.
    it "does not advance the agent's own schedule" do
      agent = make_agent("Meta")
      agent.update!(cron: "0 9 * * 1", enabled: true)
      swarm.swarm_members.create!(agent: agent, frequency: "weekly", day: 1, hour: 9)

      swarm.dispatch_due!(Time.zone.local(2026, 8, 24, 9, 0))

      expect(agent.reload.last_enqueued_at).to be_nil
    end
  end

  describe "#dispatch_all!" do
    it "runs every enabled seat regardless of rota" do
      swarm.swarm_members.create!(agent: make_agent("A"), frequency: "monthly", day: 28, hour: 3)
      swarm.swarm_members.create!(agent: make_agent("B"), frequency: "weekly", day: 5, hour: 3, enabled: false)

      runs = swarm.dispatch_all!

      expect(runs.size).to eq(1)
      expect(runs.first.trigger).to eq("manual")
    end

    it "marks the seats it queued as the rota does, so Last queued says so" do
      ran = swarm.swarm_members.create!(agent: make_agent("A"), frequency: "monthly", day: 28, hour: 3)
      off = swarm.swarm_members.create!(agent: make_agent("B"), frequency: "weekly", day: 5, hour: 3, enabled: false)
      now = Time.zone.parse("2026-09-28 10:05")

      swarm.dispatch_all!(now: now)

      expect(ran.reload.last_enqueued_at).to eq(now)
      expect(off.reload.last_enqueued_at).to be_nil
    end
  end
end
