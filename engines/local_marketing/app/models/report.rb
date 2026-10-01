# frozen_string_literal: true

# A stored run of one report. See CreateReports for why these are snapshots
# rather than a live proxy.
#
# The model deliberately knows nothing about DataForSEO. It holds a `kind`
# from Reports::Catalog, the normalized `data` that kind produced, and what
# the call cost; the definition class owns everything about how that data was
# obtained. That split is what lets a report's shape change without a
# migration, and what keeps the catalog the single place to look. Queuing and
# running one is Report::Runnable; comparing it with the run before,
# Report::Historical and Report::Trended; what reporting has cost,
# Report::Priced.
class Report < ApplicationRecord
  include Eventable
  include Historical
  include Priced
  include Runnable
  include Trended

  STATUSES = %w[queued running complete failed].freeze

  belongs_to :requested_by, class_name: "User", optional: true

  validates :kind,   presence: true, inclusion: {in: ->(_) { Reports::Catalog.keys }, message: "is not a known report"}
  validates :status, inclusion: {in: STATUSES}

  scope :recent,   -> { order(created_at: :desc) }
  scope :complete, -> { where(status: "complete") }
  scope :failed,   -> { where(status: "failed") }
  # "Still going" for the UI's polling: queued and running are one state to
  # anyone looking at a spinner.
  scope :in_flight, -> { where(status: %w[queued running]) }
  scope :of_kind,  ->(kind) { where(kind: kind.to_s) }

  STATUSES.each { |state| define_method("#{state}?") { status == state } }

  def definition = Reports::Catalog.definition_class(kind)

  def title       = definition&.title.presence || kind.humanize
  def group       = definition&.group
  def description = definition&.description

  # Deleting a snapshot removes a data point from every trend built on it.
  # The event names the kind and id rather than the row, which is gone.
  def remove
    destroy
    self.class.track_event(:deleted, kind: kind, report_id: id.to_s)
  end
end
