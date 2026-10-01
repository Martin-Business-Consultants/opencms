# frozen_string_literal: true

# A report against the runs of its kind: the latest of each, the one before,
# and whether it has gone stale for its cadence.
module Report::Historical
  extend ActiveSupport::Concern

  # How long a snapshot of a cadence stays current. Not the same question as
  # "is it late": a report nobody has run has no cadence to be late against.
  STALE_AFTER = {"weekly" => 10.days, "monthly" => 45.days}.freeze
  STALE_OTHERWISE = 30.days

  class_methods do
    # The most recent finished run of each kind, as a Hash keyed by kind.
    #
    # One query rather than one per kind: SQLite is happy to do the grouping,
    # and the index page would otherwise issue one per report.
    def latest_by_kind
      subquery = complete.group(:kind).select("MAX(id) AS id")
      where(id: subquery).index_by(&:kind)
    end

    def stale_after(cadence) = STALE_AFTER[cadence] || STALE_OTHERWISE
  end

  # The run before `self`, for the same kind — what a comparison renders
  # against. Nil for a first run, which the UI must handle: "no change" and
  # "nothing to compare with" are different statements.
  def previous
    self.class.complete.of_kind(kind).where(created_at: ...created_at).order(created_at: :desc).first
  end

  def duration
    return nil unless started_at && completed_at

    completed_at - started_at
  end

  def stale?(cadence = definition&.cadence)
    created_at < self.class.stale_after(cadence).ago
  end
end
