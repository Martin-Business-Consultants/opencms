# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::TemplateLibrary do
  describe ".seed!" do
    it "installs the shipped set" do
      expect { described_class.seed! }.to change { AgentTemplate.count }.from(0).to(described_class.all.size)
      expect(AgentTemplate.built_in.pluck(:template_key)).to include("metadata_optimizer", "content_gap")
    end

    it "is idempotent" do
      described_class.seed!

      expect { described_class.seed! }.not_to change { AgentTemplate.count }
    end

    it "leaves a site's own templates alone" do
      mine = AgentTemplate.create!(name: "Mine", instructions: "Do it my way.", capability_keys: %w[read_pages])

      described_class.seed!

      expect(mine.reload.instructions).to eq("Do it my way.")
      expect(mine.template_key).to be_nil
    end

    it "ships only capabilities the catalog knows" do
      described_class.seed!

      AgentTemplate.built_in.find_each do |template|
        expect(template.capability_keys).to eq(Agents::CapabilityCatalog.valid_keys(template.capability_keys)),
          "#{template.name} names a capability the catalog doesn't have"
        expect(template.capability_keys).to be_present
      end
    end

    it "ships valid cron expressions" do
      described_class.seed!

      AgentTemplate.built_in.where.not(cron: nil).find_each do |template|
        expect(Agent.parse_cron(template.cron)).to be_present, "#{template.name} has an unparseable cron"
      end
    end
  end

  describe "instantiating" do
    before { described_class.seed! }

    # Standing up an agent must never start it working.
    it "creates a disabled agent carrying the template's instructions" do
      template = AgentTemplate.find_by!(template_key: "metadata_optimizer")

      agent = Agent.create!(template.to_agent_attributes)

      expect(agent).not_to be_enabled
      expect(agent.instructions).to eq(template.instructions)
      expect(agent.template_key).to eq("metadata_optimizer")
      expect(template.reload).to be_installed
    end
  end
end

RSpec.describe Agents::SwarmTemplateLibrary do
  before do
    Agents::TemplateLibrary.seed!
    described_class.seed!
  end

  it "ships rosters that name agent templates which exist" do
    SwarmTemplate.built_in.find_each do |template|
      expect(template.missing_template_keys).to be_empty,
        "#{template.name} names missing agent templates: #{template.missing_template_keys.join(", ")}"
    end
  end

  describe "#instantiate!" do
    it "creates the swarm, its seats, and any agents it needs" do
      template = SwarmTemplate.find_by!(template_key: "seo_program")

      swarm = template.instantiate!

      expect(swarm).not_to be_enabled
      expect(swarm.swarm_members.count).to eq(template.member_rows.size)
      expect(Agent.where(template_key: "metadata_optimizer")).to exist
      expect(swarm.swarm_members.map(&:schedule_label)).to all(be_present)
    end

    # Two agents with the same instructions on the same site is duplicate
    # work that reads as a full roster.
    it "reuses an agent already built from a template rather than duplicating it" do
      existing = Agent.create!(AgentTemplate.find_by!(template_key: "technical_seo").to_agent_attributes)

      swarm = SwarmTemplate.find_by!(template_key: "technical_health").instantiate!

      expect(Agent.where(template_key: "technical_seo").count).to eq(1)
      expect(swarm.agents).to include(existing)
    end

    it "staggers the roster rather than firing it all at once" do
      swarm = SwarmTemplate.find_by!(template_key: "seo_program").instantiate!
      slots = swarm.swarm_members.map { |m| [m.frequency, m.day, m.hour] }

      expect(slots.uniq.size).to eq(slots.size)
    end
  end
end
