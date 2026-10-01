# frozen_string_literal: true

# A runnable agent: instructions, the capabilities it may use, what part of
# the site it works, and how often.
#
# There is no built-in-agent class hierarchy the way Lumin/ads has one,
# because there is nothing for such a class to do. Ads' agent classes exist
# to assemble Ruby tool objects and drive a model in-process; here the model
# runs on a worker and the tools are the `cms` CLI, so an agent is fully
# described by its data. The starter set lives in `Agents::TemplateLibrary`
# and instantiates into an ordinary editable row — same "pick one and tune
# it" flow, one code path instead of three.
#
# Cadence lives here rather than in a separate schedule table for the same
# reason: every agent is already a row.
class Agent < ApplicationRecord
  include ScopableContent
  include Eventable
  include Scheduled

  has_many :agent_runs,    dependent: :nullify
  has_many :swarm_members, dependent: :destroy
  has_many :swarms, through: :swarm_members

  validates :name, presence: true, uniqueness: true, length: {maximum: 120}
  validates :instructions, presence: true, length: {maximum: 20_000}
  validates :description, length: {maximum: 2_000}, allow_blank: true
  validate  :validate_capability_keys
  validate  :validate_cron

  scope :ordered,   -> { order(:name) }
  scope :enabled,   -> { where(enabled: true) }
  scope :scheduled, -> { enabled.where.not(cron: [nil, ""]) }
  scope :due, ->(now = Time.current) { scheduled.where("next_due_at IS NULL OR next_due_at <= ?", now) }

  before_validation :normalize_capability_keys

  # The role of whoever is saving this agent, when a person is (the admin
  # form). See #validate_publish_grant.
  attr_accessor :granted_by
  before_save :recompute_next_due_at,
    if: -> { will_save_change_to_cron? || will_save_change_to_enabled? || will_save_change_to_last_enqueued_at? }

  def icon = self[:icon].presence || "sparkles"

  # --- the shipped library -------------------------------------------------
  #
  # An agent made from a template remembers which VERSION it came from. The
  # library can then move on and say so, per agent, instead of improvements
  # reaching nobody — which is what happened while a row knew only that it was
  # once a "Metadata Optimizer".
  #
  # Pinned, never followed: editing an agent is expected here, so an upgrade
  # is something offered and taken, with the diff shown first.

  def template = template_key.present? ? Agents::Registry.find(template_key) : nil

  def from_library? = template.present?

  def latest_template_version = template&.version

  def upgradable?
    latest_template_version.present? && latest_template_version > template_version.to_i
  end

  # What taking the upgrade would change, field by field. Shown rather than
  # applied: a site may have edited any of these, and "your instructions
  # will be replaced" is a different sentence from "a new version exists".
  # Field by field, labelled the way the form labels it — the reader deciding
  # whether to take an upgrade is looking at the same words they edited.
  FIELD_LABELS = {
    "name" => "Name", "description" => "Description", "category" => "Category",
    "icon" => "Icon", "instructions" => "Instructions", "capability_keys" => "Capabilities",
    "preferred_model" => "Model tier", "cron" => "Cadence"
  }.freeze

  def library_changes
    shipped = template or return []

    shipped.to_agent_attributes.filter_map do |field, incoming|
      mine = public_send(field)
      next if mine.to_s == incoming.to_s

      {field: field.to_s, label: FIELD_LABELS.fetch(field.to_s, field.to_s.humanize),
       from: display(mine), to: display(incoming)}
    end
  end

  def take_library_upgrade!
    shipped = template or return false
    return false unless upgradable?

    update!(shipped.to_agent_attributes.merge(template_version: shipped.version))
  end

  # The tier this agent runs at, and the model that resolves to. `tier` and a
  # raw model id both live in `preferred_model` on purpose: tiers arrived
  # after the rows did, and accepting either is what let them arrive without a
  # migration that rewrites every agent — or a stored id becoming a broken run.
  def tier = Ai::Models.tier_of(preferred_model.presence || template&.tier)

  def resolved_model = Ai::Models.resolve(preferred_model.presence || template&.tier)

  # How much room a run gets. Stated in the brief for the harness to honour —
  # the CMS does not execute runs, so this is a limit it declares, not one it
  # enforces.
  def budget = template&.budget || Agents::Budget.default

  def capability_labels = Agents::CapabilityCatalog.labels(capability_keys)

  def writes? = Agents::CapabilityCatalog.writes?(capability_keys)

  def publishes? = Agents::CapabilityCatalog.publishes?(capability_keys)

  # Capabilities this agent is configured to use that `role` doesn't grant.
  # Surfaced on the agent row so a misconfiguration reads as a warning here
  # rather than as a 403 halfway through a run on a worker box.
  def missing_capabilities(role) = Agents::CapabilityCatalog.missing_capabilities(capability_keys, role)

  # Queue a run. The brief is snapshotted now, so editing the agent later
  # changes what its next run does and never what a finished run did.
  def dispatch!(trigger: "manual", triggered_by: nil, swarm: nil, swarm_member: nil, priority: 0)
    run = AgentRun.create!(
      agent: self,
      agent_name: name,
      swarm: swarm,
      swarm_member: swarm_member,
      trigger: trigger,
      triggered_by: triggered_by,
      priority: priority,
      brief: Agents::RunBrief.new(self, swarm: swarm, swarm_member: swarm_member).to_h,
      expires_at: AgentRun::DEFAULT_TTL.from_now
    )
    # With a Zen key the run executes in this process (AgentRun::Executable);
    # without one it waits for a worker box to claim it through the API.
    run.execute_later if Ai::Zen.configured?
    run
  end

  # Marks the cadence as fired. Separate from dispatch! because a swarm run
  # advances its member's rota, not the agent's own schedule.
  def mark_enqueued!(at: Time.current)
    update!(last_enqueued_at: at)
  end

  def cadence_label
    return "manual only" if cron.blank?

    parsed = self.class.parse_cron(cron)
    parsed ? "#{parsed.original}#{" (paused)" unless enabled?}" : cron
  end

  def compute_next_due_at(now: Time.current)
    return nil unless enabled?
    return nil if cron.blank?

    parsed = self.class.parse_cron(cron)
    return nil unless parsed

    parsed.next_time(last_enqueued_at || now - 1.minute).to_t
  rescue StandardError
    nil
  end

  def self.parse_cron(expression)
    Fugit.parse_cron(expression.to_s)
  end

  private

  def display(value) = value.is_a?(Array) ? value.join(", ") : value.to_s

  def normalize_capability_keys
    self.capability_keys = Agents::CapabilityCatalog.valid_keys(capability_keys)
  end

  # Runs after normalization strips unknown keys, so this only fires when a
  # selection was ENTIRELY unrecognised — an agent with no capabilities can't
  # do anything, and would otherwise sit in the roster looking healthy.
  def validate_capability_keys
    errors.add(:capability_keys, "must include at least one capability") if capability_keys.blank?
    validate_publish_grant
  end

  # Publishing is the publish capability's job (PublicationGate), so a person
  # can hand an agent a publish key only if they could publish themselves.
  # Checked for keys this save adds, and only when the saver's role is known
  # (`granted_by`, set by the admin form): an agent an admin granted keeps
  # its key when someone else edits its instructions.
  def validate_publish_grant
    return if granted_by.nil?

    added = Array(capability_keys) - Array(capability_keys_was)
    missing = Agents::CapabilityCatalog.missing_capabilities(added & Agents::CapabilityCatalog::PUBLISH.keys, granted_by)
    errors.add(:capability_keys, "can only grant publishing with #{missing.to_sentence} yourself") if missing.any?
  end

  def validate_cron
    return if cron.blank?

    errors.add(:cron, "is not a valid cron expression") unless self.class.parse_cron(cron)
  end

  def recompute_next_due_at
    self.next_due_at = compute_next_due_at
  end
end
