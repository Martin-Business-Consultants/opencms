# frozen_string_literal: true

# Two-phase delete: `discard!` flips `deleted_at` to now (the record vanishes
# from default scoped reads but stays in the DB for ~30 days), `restore!`
# clears it back to nil. Hard deletes are still available via
# `destroy_permanently!` and are used by the daily purge job.
#
# A default_scope filters discarded rows from every read. To peek behind it:
#
#   Page.with_discarded.find(id)   # see all rows
#   Page.discarded                 # only the trashed ones
#   Page.kept                      # explicit kept-only (same as default)
#
# `dependent: :destroy` callbacks on associations do NOT fire when a record
# is discarded — that's deliberate. Versions, references, attached files etc.
# stick around so a restore brings the record back fully intact. They're
# only torn down when `destroy_permanently!` runs (i.e. by the purge job).
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    default_scope { where(deleted_at: nil) }

    scope :kept,           -> { unscope(where: :deleted_at).where(deleted_at: nil) }
    scope :discarded,      -> { unscope(where: :deleted_at).where.not(deleted_at: nil) }
    scope :with_discarded, -> { unscope(where: :deleted_at) }

    # Preserve the unmodified destroy as `destroy_permanently!` so the
    # purge job (and tests) can still hard-delete.
    alias_method :destroy_permanently!, :destroy!
  end

  def discarded?
    deleted_at.present?
  end

  def kept?
    !discarded?
  end

  # Both skip validations (`update_attribute`) but still run callbacks, so the
  # deleted/restored webhooks fire. Trashing is not a content edit: a record
  # whose stored content no longer passes current validation (e.g. legacy
  # blocks written before a block type's schema tightened) must still be
  # deletable, and must come back exactly as it was.
  def discard!
    return self if discarded?

    update_attribute(:deleted_at, Time.current)
    self
  end

  def restore!
    return self unless discarded?

    update_attribute(:deleted_at, nil)
    self
  end
end
