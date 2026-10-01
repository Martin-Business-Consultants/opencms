# frozen_string_literal: true

# Editorial review request — an author without publish capability submits
# one of these to ask a reviewer to publish their work. The reviewer can
# approve (which flips the underlying record's status to `published`),
# request changes (leaves the record draft with comments attached), or
# the author can cancel before either decision is made.
#
# `state` enumerates the lifecycle. Once it leaves `pending`, mutations
# stop — the request becomes part of the audit trail.
class ReviewRequest < ApplicationRecord
  include Eventable

  STATES = %w[pending approved changes_requested cancelled].freeze

  belongs_to :reviewable,   polymorphic: true
  belongs_to :requested_by, class_name: "User"
  belongs_to :reviewer,     class_name: "User", optional: true

  validates :state, inclusion: {in: STATES}
  validates :comment, length: {maximum: 5_000}, allow_blank: true
  validates :decision_comment, length: {maximum: 5_000}, allow_blank: true
  validate  :validate_one_pending_per_reviewable, on: :create

  scope :pending,            -> { where(state: "pending") }
  scope :resolved,           -> { where.not(state: "pending") }
  scope :for_reviewable,     ->(record) { where(reviewable: record) }

  # The API's list: pending newest first, resolved most recently decided
  # first, anything else newest first.
  def self.in_state(state)
    case state.to_s
    when "pending"  then pending.order(created_at: :desc)
    when "resolved" then resolved.order(decided_at: :desc)
    else order(created_at: :desc)
    end
  end

  # What a review is about, as the API and its audit rows describe it.
  def self.summary_of(record)
    {
      type:   record.class.name,
      id:     record.id,
      slug:   record.try(:path) || record.try(:slug),
      label:  record.try(:title) || record.try(:slug) || "##{record.id}",
      status: record.try(:status)
    }
  end

  # A writer who can't publish asked to (PublicationGate held it back): the
  # record's open request, or a new one. Approving it publishes the record.
  def self.request_publication(record, by:, comment: nil)
    pending.for_reviewable(record).first || create!(reviewable: record, requested_by: by, comment: comment).tap do |request|
      request.track_event(:created, reviewable: summary_of(record))
    end
  end

  def pending?
    state == "pending"
  end

  def approve!(by:, comment: nil)
    return false unless pending?

    transaction do
      reviewable.update!(status: "published") if reviewable.respond_to?(:status)
      update!(
        state:            "approved",
        reviewer:         by,
        decision_comment: comment,
        decided_at:       Time.current
      )
    end
    track_event(:approved)
    true
  end

  def request_changes!(by:, comment: nil)
    return false unless pending?

    update!(
      state:            "changes_requested",
      reviewer:         by,
      decision_comment: comment,
      decided_at:       Time.current
    )
    track_event(:changes_requested)
    true
  end

  def cancel!(by:)
    return false unless pending?
    return false unless by.id == requested_by_id

    update!(state: "cancelled", decided_at: Time.current)
    track_event(:cancelled)
    true
  end

  private

  def validate_one_pending_per_reviewable
    return unless reviewable && self.class.pending.where(reviewable: reviewable).exists?

    errors.add(:base, "a review is already pending for this record")
  end
end
