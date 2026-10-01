# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockType::Tracked do
  let(:block_type) { BlockType.create!(slug: "banner", label: "Banner", fields: []) }

  it "records the admin's names" do
    block_type.track_creation
    expect(AuditLog.last).to have_attributes(action: "block_type.created", target: block_type, metadata: {"slug" => "banner"})

    block_type.track_update
    expect(AuditLog.last.action).to eq("block_type.updated")
  end

  it "keeps rows written under the API's former names findable under the current ones" do
    AuditLog.create!(action: "block_types.create", metadata: {"slug" => "old"})

    expect(AuditLog.filtered(action: "block_type.created").pluck(:action)).to include("block_types.create")
    expect(AuditLog.known_actions).not_to include("block_types.create")
    expect(AuditLog.last.current_action).to eq("block_type.created")
  end
end
