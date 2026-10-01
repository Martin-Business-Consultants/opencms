# frozen_string_literal: true

# A saved version of a page or an entry (PageVersion, CollectionEntryVersion):
# what it holds, and what restoring it would change on the record now, as a
# Revision::Diff (the same readable diff the review queue shows).
module VersionSnapshot
  extend ActiveSupport::Concern

  # Revision::Diff reads a revision's proposed payload against the record's
  # snapshot; a version plays the proposal, the record as it is now the base.
  Comparison = Struct.new(:payload, :base_snapshot) do
    def stale? = false

    def drifted_keys = []
  end

  # The attributes this version holds, as the record would take them back.
  def snapshot
    self.class::SNAPSHOT_ATTRIBUTES.index_with { public_send(it) }
  end

  # Only the attributes that differ from the record now.
  def changes_from_current
    current = versioned_record.slice(*self.class::SNAPSHOT_ATTRIBUTES)
    changed = snapshot.reject { |key, value| Revision.normalize(value) == Revision.normalize(current[key]) }
    Revision::Diff.new(Comparison.new(changed, current)).call
  end

  def matches_current?
    changes_from_current[:fields].empty?
  end
end
