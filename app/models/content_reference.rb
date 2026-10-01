# frozen_string_literal: true

# Denormalized index of references that live inside Page blocks or
# CollectionEntry frontmatter / markdown. Maintained by `sync_references` on
# the owner side. Lets us answer "which pages use asset X?" without scanning
# JSON, and clean up when an asset/record is deleted.
class ContentReference < ApplicationRecord
  belongs_to :owner, polymorphic: true

  # The records that point at one thing, a page at a time: [reference, owner]
  # pairs, one per owner (a record that links twice is listed once), plus the
  # total number of owners.
  def self.owners_of(ref_type:, ref_id:, kind: nil, page: 1, per: 50)
    scope = where(ref_type: ref_type, ref_id: ref_id)
    scope = scope.where(kind: kind) if kind.present?
    total = scope.distinct.count("(owner_type || ':' || owner_id)")

    refs = scope.order(created_at: :asc).offset((page - 1) * per).limit(per).includes(:owner)
    owned = refs.select(&:owner).uniq { |ref| [ref.owner.class.name, ref.owner.id] }
    [owned, total]
  end
end
