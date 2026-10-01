# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent do
  def build_agent(**attrs)
    described_class.new({
      name: "Metadata",
      instructions: "Fix titles.",
      capability_keys: %w[manifest read_pages]
    }.merge(attrs))
  end

  describe "capability keys" do
    it "drops keys that aren't in the catalog" do
      agent = build_agent(capability_keys: %w[read_pages not_a_real_tool])
      agent.validate

      expect(agent.capability_keys).to eq(["read_pages"])
    end

    # An agent whose whole selection was bogus can do nothing, and would
    # otherwise sit in the roster looking healthy.
    it "is invalid when nothing survives normalization" do
      agent = build_agent(capability_keys: %w[nonsense])

      expect(agent).not_to be_valid
      expect(agent.errors[:capability_keys]).to be_present
    end
  end

  describe "cron" do
    it "rejects an unparseable expression" do
      expect(build_agent(cron: "every other tuesday")).not_to be_valid
    end

    it "computes next_due_at only when enabled" do
      agent = build_agent(cron: "0 9 * * 1", enabled: false)
      agent.save!
      expect(agent.next_due_at).to be_nil

      agent.update!(enabled: true)
      expect(agent.next_due_at).to be_present
    end

    it "leaves a manual-only agent out of the due scope" do
      build_agent(name: "Manual", cron: nil, enabled: true).save!

      expect(described_class.due).to be_empty
    end
  end

  describe "#dispatch!" do
    it "queues a run carrying a frozen brief" do
      agent = build_agent(cron: "0 9 * * 1")
      agent.save!

      run = agent.dispatch!(trigger: "schedule")

      expect(run).to be_queued
      expect(run.agent_name).to eq("Metadata")
      expect(run.brief.dig("agent", "instructions")).to eq("Fix titles.")
      expect(run.expires_at).to be_present
    end

    # The whole reason the brief is a snapshot: a run page a month from now
    # has to show the instructions that actually produced it.
    it "does not rewrite an existing run's brief when the agent changes" do
      agent = build_agent
      agent.save!
      run = agent.dispatch!

      agent.update!(instructions: "Something else entirely.")

      expect(run.reload.brief.dig("agent", "instructions")).to eq("Fix titles.")
    end
  end

  describe "scope" do
    it "reports the whole site when no scopes are set" do
      agent = build_agent
      agent.save!

      expect(agent).to be_whole_site
      expect(agent.scopes_for_brief).to eq([{kind: "site"}])
    end

    it "describes narrowed scopes in prose and in structure" do
      agent = build_agent
      agent.save!
      agent.content_scopes.create!(scope_kind: "collection", value: "posts")
      agent.content_scopes.create!(scope_kind: "path_prefix", value: "guides/")

      expect(agent.reload).not_to be_whole_site
      expect(agent.scope_label).to include("collection “posts”", "pages under /guides")
      expect(agent.scopes_for_brief).to contain_exactly(
        {kind: "collection", value: "posts"},
        {kind: "path_prefix", value: "/guides"}
      )
    end
  end

  describe "#missing_capabilities" do
    it "names capabilities the role doesn't grant" do
      agent = build_agent(capability_keys: %w[read_pages write_pages publish_pages])
      agent.save!
      role = Role.new(permissions: %w[pages:read pages:write])

      expect(agent.missing_capabilities(role)).to eq(["pages:publish"])
    end
  end
end
