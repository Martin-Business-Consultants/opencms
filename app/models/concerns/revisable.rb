# frozen_string_literal: true

# The review gate on the record: a change to something in front of visitors,
# by someone who can't publish it, is filed as a Revision for a reviewer
# instead of applied. The admin (ContentEditing), the API (GatedWrites) and
# the agent tools all ask the record, so the rule can't drift between them.
#
# "In front of visitors" means published for pages and entries, and simply
# existing for globals, which have no draft state. A draft or a new record
# isn't gated here; what its write can't do without the publish capability
# is publish it (PublicationGate).
#
#   if page.review_gated?(can_publish: false)
#     proposal = page.propose(attributes, by: user, source: "ui")
#     proposal.outcome # => :proposed, :unchanged, :conflict or :invalid
#   end
module Revisable
  extend ActiveSupport::Concern

  # What proposing came to. `revision` is the one filed (:proposed) or the one
  # already waiting (:conflict); `error` is the save's RecordInvalid when the
  # revision couldn't be filed (:conflict, :invalid).
  Proposal = Data.define(:outcome, :revision, :error) do
    def self.unchanged = new(:unchanged, nil, nil)

    def proposed? = outcome == :proposed
  end

  def review_gated?(can_publish:)
    !can_publish && live_for_review?
  end

  # Whether the record, as stored, is in front of visitors. Read from the
  # database value, so assigning a new status first doesn't change the answer.
  def live_for_review?
    respond_to?(:status) ? status_in_database.to_s == "published" : persisted?
  end

  # Files `attributes` as a revision, leaving the record as it is. Only the
  # fields a revision may carry count (Revision::REVISABLE_ATTRIBUTES), so a
  # write that changes nothing else is :unchanged. A second proposal while one
  # is pending is a :conflict naming the pending one.
  def propose(attributes, by:, source:, note: nil, api_token: nil, run_id: nil, actor: Current.actor)
    return Proposal.unchanged if Revision.filter_attributes(self, attributes).empty?

    revision = Revision.propose(record: self, attributes: attributes, author: by, source: source,
      note: note, api_token: api_token, run_id: run_id, actor: actor)
    Proposal.new(:proposed, revision, nil)
  rescue ActiveRecord::RecordInvalid => e
    pending = Revision.pending.for_revisable(self).first
    pending ? Proposal.new(:conflict, pending, e) : Proposal.new(:invalid, nil, e)
  end
end
