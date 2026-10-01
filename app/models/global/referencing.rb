# frozen_string_literal: true

# What a global links to (assets, pages, entries) from its data, stored as
# content references so "what uses this?" is a query rather than a scan.
# Rewritten on every save.
module Global::Referencing
  extend ActiveSupport::Concern

  included do
    has_many :content_references, as: :owner, dependent: :delete_all

    after_save :sync_references
  end

  private

  def sync_references
    new_refs = []
    BlockType.each_reference_in(fields, data || {}) do |kind, ref_type, ref_id|
      new_refs << {
        owner_type: "Global",
        owner_id:   id,
        ref_type:   ref_type.to_s,
        ref_id:     ref_id.to_s,
        kind:       kind.to_s,
        position:   0,
        created_at: Time.current
      }
    end

    ContentReference.transaction do
      ContentReference.where(owner_type: "Global", owner_id: id).delete_all
      ContentReference.insert_all(new_refs) if new_refs.any?
    end
  end
end
