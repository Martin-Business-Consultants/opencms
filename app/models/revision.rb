# frozen_string_literal: true

# A proposed change that hasn't touched the live record yet.
#
# The gate exists because of one asymmetry: `ReviewRequest` covers "an author
# wrote a draft, please publish it", but an API client editing an already
# published page has nothing to review — `update!` puts the change live and
# the only trace is a version snapshot after the fact. A Revision is the other
# half: the attributes sit here, the record keeps serving what it served, and
# somebody with the publish capability decides.
#
# Three pieces of state, and each earns its place:
#
#   payload        what the author wants the record to say
#   base_snapshot  the same fields as they were when the change was proposed
#   base_version_id the content version current at that moment
#
# Diffing against `base_snapshot` rather than against the record as it stands
# at review time shows the reviewer the change the author actually made. The
# record is then compared separately, so a revision proposed against content
# that has since moved is flagged (`stale?`) instead of silently clobbering
# whatever landed in between.
class Revision < ApplicationRecord
  include Eventable
  include Proposal

  STATES = %w[pending applied rejected superseded].freeze
  # "agent" is an in-process agent run (the Agents plugin runs one in-process) — kept distinct from
  # "api" so the review queue can say a machine proposed the change.
  SOURCES = %w[api ui agent].freeze

  # Per type: what a revision is allowed to carry. `status` is deliberately
  # absent everywhere — moving a record between draft and published is the
  # publish capability's job, and letting a gated write smuggle it through
  # would make the gate decorative.
  REVISABLE_ATTRIBUTES = {
    "Page" => %w[title slug locale blocks frontmatter seo],
    "CollectionEntry" => %w[title slug locale body_markdown blocks frontmatter seo],
    "Global" => %w[name description icon data]
  }.freeze

  belongs_to :revisable, polymorphic: true
  belongs_to :author,     class_name: "User", optional: true
  belongs_to :decided_by, class_name: "User", optional: true
  # Either kind of credential can propose one: a person's ApiToken, or a
  # ServiceToken with no person behind it (an agent on USER_AGENT_TOKEN).
  belongs_to :api_token,  polymorphic: true, optional: true

  validates :state,  inclusion: {in: STATES}
  validates :source, inclusion: {in: SOURCES}
  validates :note, :decision_comment, length: {maximum: 5_000}, allow_blank: true
  validate  :payload_present, on: :create
  validate  :one_pending_per_revisable, on: :create

  scope :pending,  -> { where(state: "pending") }
  scope :resolved, -> { where.not(state: "pending") }
  scope :recent,   -> { order(created_at: :desc) }
  scope :for_revisable, ->(record) { where(revisable: record) }

  # Records a proposal without touching `record`. `attributes` is whatever the
  # controller permitted; anything outside the type's allow-list is dropped
  # here rather than at apply time, so what a reviewer sees is exactly what
  # approving will write.
  #
  # run_id: the agent run proposing it, when one is (the in-process gate, or
  # an API write carrying agent_run_id like `cms recommend` does). The Agents
  # plugin links it (proposed_during); without the plugin it's ignored.
  def self.propose!(record:, attributes:, author: nil, source: "api", note: nil, api_token: nil, run_id: nil)
    payload = filter_attributes(record, attributes)

    revision = new(
      revisable: record,
      payload: payload,
      base_snapshot: snapshot(record, payload.keys),
      base_version_id: current_version_id(record),
      author: author,
      api_token: api_token,
      source: source,
      note: note.presence
    )
    revision.proposed_during(run_id) if run_id.present?
    revision.save!
    revision
  end

  # Drops unknown/disallowed keys and anything that isn't actually a change —
  # an API client that PUTs a whole record shouldn't produce a revision listing
  # every untouched field as "changed".
  # A proposal someone made (the review gate, the editor), recorded as such.
  # Revision.propose! alone is for callers that record their own events.
  #
  # actor: who the audit row credits, when it isn't the request's (an agent
  # run proposing from a background job). An agent's row also names its run.
  def self.propose(record:, attributes:, author: nil, source: "api", note: nil, api_token: nil, run_id: nil, actor: Current.actor)
    propose!(record: record, attributes: attributes, author: author, source: source, note: note, api_token: api_token, run_id: run_id).tap do |revision|
      run = {agent_run: run_id} if source == "agent" && run_id.present?
      revision.track_event(:proposed, actor: actor, revisable: "#{record.class.name}##{record.id}", label: revision.label,
        fields: revision.changed_keys, **run.to_h)
    end
  end

  def self.filter_attributes(record, attributes)
    allowed = REVISABLE_ATTRIBUTES.fetch(record.class.name, [])
    attributes.to_h.stringify_keys.slice(*allowed).reject do |key, value|
      normalize(record.public_send(key)) == normalize(value)
    end
  end

  def self.snapshot(record, keys)
    keys.index_with { |key| record.public_send(key) }
  end

  def self.current_version_id(record)
    record.respond_to?(:versions) ? record.versions.order(:id).last&.id : nil
  end

  # JSON round-trips turn symbol keys into strings and integers stay integers;
  # comparing the parsed forms keeps "unchanged" from depending on how the
  # value happened to arrive.
  def self.normalize(value)
    case value
    when Hash  then value.to_h { |k, v| [k.to_s, normalize(v)] }
    when Array then value.map { |v| normalize(v) }
    when ActionController::Parameters then normalize(value.to_unsafe_h)
    else value
    end
  end

  def pending? = state == "pending"

  def changed_keys = payload.keys

  # The record moved under this revision: someone else edited one of the same
  # fields (or the content version advanced) after it was proposed.
  def stale?
    return false unless revisable

    base_version_id != self.class.current_version_id(revisable) || drifted_keys.any?
  end

  # Which of this revision's fields changed underneath it — the reviewer needs
  # the list, not just the fact.
  def drifted_keys
    return [] unless revisable

    base_snapshot.keys.reject do |key|
      next true unless revisable.respond_to?(key)

      self.class.normalize(base_snapshot[key]) == self.class.normalize(revisable.public_send(key))
    end
  end

  def diff = Revision::Diff.new(self).call

  # Who to credit in the queue. A service token has no user, so its name is
  # the only identity there is — and it's a better one than an email anyway.
  def proposed_by
    author&.email.presence || api_token.try(:name) || "unknown"
  end

  # Writes the payload to the record. Nothing here forces the caller's hand on
  # a stale revision — that's a decision the controller surfaces to a human —
  # but the applied snapshot records what the record actually looked like at
  # the moment it was written, so the audit trail stays honest either way.
  def apply!(by:, comment: nil, forced: false)
    return false unless pending?

    transaction do
      revisable.update!(payload)
      update!(
        state: "applied",
        decided_by: by,
        decision_comment: comment.presence,
        decided_at: Time.current
      )
      supersede_others!
    end
    track_event(:applied, revisable: "#{revisable_type}##{revisable_id}", fields: changed_keys, forced: forced)
    true
  end

  def reject!(by:, comment: nil)
    return false unless pending?

    update!(
      state: "rejected",
      decided_by: by,
      decision_comment: comment.presence,
      decided_at: Time.current
    )
    track_event(:rejected, fields: changed_keys)
    true
  end

  # Survives the record being deleted out from under a resolved revision —
  # the queue still has to render its history.
  def label
    return "#{revisable_type} ##{revisable_id} (deleted)" if revisable.nil?

    revisable.try(:title).presence || revisable.try(:name).presence ||
      revisable.try(:slug).presence || "##{revisable_id}"
  end

  private

  # A second pending revision on the same record would be reviewed against a
  # base that no longer holds once the first is applied.
  def supersede_others!
    self.class.pending.for_revisable(revisable).where.not(id: id)
      .update_all(state: "superseded", decided_at: Time.current, updated_at: Time.current)
  end

  def payload_present
    errors.add(:base, "no changes to review") if payload.blank?
  end

  def one_pending_per_revisable
    return unless revisable && self.class.pending.for_revisable(revisable).exists?

    errors.add(:base, "a revision is already pending for this record")
  end
end
