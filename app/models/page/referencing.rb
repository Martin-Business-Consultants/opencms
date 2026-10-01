# frozen_string_literal: true

# What a page links to (other pages, entries, assets, collections), from its
# blocks and fields, stored as content references so "what uses this?" is a
# query rather than a scan. Rewritten on every save.
module Page::Referencing
  extend ActiveSupport::Concern

  included do
    has_many :content_references, as: :owner, dependent: :delete_all

    after_save :sync_references
  end

  private

  def sync_references
    new_refs = []

    Array(blocks).each_with_index do |hash, position|
      next unless hash.is_a?(Hash)

      block_type = BlockType.find_by(slug: hash["type"])
      next unless block_type

      block_type.each_reference(hash["data"] || {}) do |kind, ref_type, ref_id|
        new_refs << reference_row(kind, ref_type, ref_id, position)
      end
    end

    BlockType.each_reference_in(fields, frontmatter || {}) do |kind, ref_type, ref_id|
      new_refs << reference_row(kind, ref_type, ref_id, -1)
    end

    ContentReference.transaction do
      ContentReference.where(owner_type: "Page", owner_id: id).delete_all
      ContentReference.insert_all(new_refs) if new_refs.any?
    end
  end

  def reference_row(kind, ref_type, ref_id, position)
    {
      owner_type: "Page",
      owner_id: id,
      ref_type: ref_type.to_s,
      ref_id: ref_id.to_s,
      kind: kind.to_s,
      position: position,
      created_at: Time.current
    }
  end
end
