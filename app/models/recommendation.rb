# frozen_string_literal: true

# An advisory finding from an agent run — the third thing that can land in
# the approvals queue.
#
# `Revision` covers "change these fields on this record" and `ReviewRequest`
# covers "publish this draft". Neither fits most SEO findings: a topic with
# demand and no page yet, two pages competing for one query, a section with
# no internal links into it. There is no record to edit, so there is nothing
# to file a revision against — and with nowhere to put them, those findings
# die in a run summary nobody reads.
#
# Accepting one does NOT write content. It records the decision and leaves
# `proposed_changes` for a human, or a follow-up run, to apply through the
# ordinary gated-write path. The CMS keeps exactly one way to change content
# and one gate in front of it; this adds a queue, not a second door.
class Recommendation < ApplicationRecord
  include Eventable

  KINDS = %w[
    content_gap metadata schema internal_linking cannibalization
    technical freshness accessibility
  ].freeze
  STATUSES = %w[open accepted dismissed actioned].freeze
  # 0 means "unrated" — an agent that doesn't score its findings shouldn't
  # have them all sort as the lowest priority.
  IMPACTS = (0..5).freeze

  include Filing
  include Subjects
  include Listing

  belongs_to :subject,     polymorphic: true, optional: true
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :kind,   inclusion: {in: KINDS, message: "must be one of: #{KINDS.join(", ")}"}
  validates :status, inclusion: {in: STATUSES}
  validates :impact, inclusion: {in: IMPACTS}
  validates :title, presence: true, length: {maximum: 300}
  validates :body,  length: {maximum: 20_000}, allow_blank: true
  validates :decision_comment, length: {maximum: 5_000}, allow_blank: true

  scope :open,     -> { where(status: "open") }
  scope :resolved, -> { where.not(status: "open") }
  scope :recent,   -> { order(created_at: :desc) }
  # Highest impact first, then newest. Unrated findings sort last within
  # their date rather than leading the queue.
  scope :prioritized, -> { order(impact: :desc, created_at: :desc) }

  STATUSES.each { |state| define_method("#{state}?") { status == state } }

  def resolvable? = open?

  # Does this name a concrete edit someone could make? Advisory findings
  # (a content gap) don't, and the queue shouldn't offer an "apply" affordance
  # that has nothing to apply.
  def actionable? = subject.present? && proposed_changes.present?

  def accept!(by:, comment: nil)
    resolve!(to: "accepted", by: by, comment: comment)
  end

  def dismiss!(by:, comment: nil)
    resolve!(to: "dismissed", by: by, comment: comment)
  end

  # "Someone has since done this." Distinct from accepted, which means the
  # decision was made but the work may still be outstanding.
  def mark_actioned!(by:, comment: nil)
    resolve!(to: "actioned", by: by, comment: comment)
  end

  # Survives its subject being deleted — a resolved finding still has to
  # render in the history.
  def subject_label
    return nil if subject_type.blank?
    return "#{subject_type} ##{subject_id} (deleted)" if subject.nil?

    subject.try(:title).presence || subject.try(:name).presence ||
      subject.try(:slug).presence || "##{subject_id}"
  end

  def kind_label = kind.tr("_", " ")

  private

  # A single conditional UPDATE, so two reviewers resolving at once can't
  # both win and overwrite each other's decision.
  def resolve!(to:, by:, comment: nil)
    changed = self.class.unscoped.where(id: id, status: "open").update_all(
      status: to,
      resolved_by_id: by&.id,
      resolved_at: Time.current,
      decision_comment: comment.presence,
      updated_at: Time.current
    )
    return false unless changed == 1

    reload
    true
  end
end
