# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockType::Seedable do
  before { BlockType.delete_all }

  it "installs the starter pack on an empty site and records it" do
    expect(BlockType.seed).to eq(BlockType::Defaults::ALL.size)

    expect(BlockType.count).to eq(BlockType::Defaults::ALL.size)
    expect(AuditLog.last).to have_attributes(action: "block_types.seeded", metadata: {"count" => BlockType::Defaults::ALL.size})
  end

  it "refuses once the site has block types" do
    BlockType.create!(slug: "mine", label: "Mine", fields: [])

    expect(BlockType.seed).to be_nil
    expect(BlockType.pluck(:slug)).to eq(%w[mine])
  end

  it "includes the block types enabled plugins ship" do
    pack = {slug: "plugin_card", label: "Plugin card", category: "Plugin", fields: [{"name" => "title", "type" => "string"}]}
    allow(Cms::Plugins).to receive(:enabled_block_type_packs)
      .and_return(demo: Cms::Plugins::BlockTypePack.new(block_types: [pack], package: nil))

    expect(BlockType.seed).to eq(BlockType::Defaults::ALL.size + 1)
    expect(BlockType.find_by!(slug: "plugin_card")).to have_attributes(label: "Plugin card", built_in: true)
  end
end
