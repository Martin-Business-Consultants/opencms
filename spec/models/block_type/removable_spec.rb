# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockType::Removable do
  def make(slug) = BlockType.create!(slug: slug, label: slug.titleize, fields: [])

  it "deletes one, recording it first under the admin's name" do
    block_type = make("banner")

    block_type.remove

    expect(BlockType.exists?(block_type.id)).to be(false)
    expect(AuditLog.last).to have_attributes(action: "block_type.deleted", target_id: block_type.id, metadata: {"slug" => "banner"})
  end

  it "deletes a set under one event" do
    BlockType.remove_all([make("a"), make("b")])

    expect(AuditLog.last).to have_attributes(action: "block_type.bulk_deleted", metadata: {"count" => 2, "slugs" => %w[a b]})
    expect(BlockType.count).to eq(0)
  end
end
