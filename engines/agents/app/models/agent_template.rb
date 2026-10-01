# frozen_string_literal: true

# A reusable agent blueprint — name, instructions, capabilities and a
# suggested cadence. Templates don't run; you instantiate one into an Agent,
# which starts DISABLED so standing one up never silently begins work.
#
# Rows with a `template_key` came from `Agents::TemplateLibrary` and are
# re-seeded in place on upgrade; rows without one were written by the site
# and are never touched by a seed.
class AgentTemplate < ApplicationRecord
  include Eventable

  has_many :content_scopes, as: :scopable, dependent: :destroy

  validates :name, presence: true, uniqueness: true, length: {maximum: 120}
  validates :instructions, presence: true, length: {maximum: 20_000}
  validates :template_key, uniqueness: true, allow_nil: true
  validate  :validate_cron

  # NULLs last, then category, then name — so the shipped SEO set groups
  # together and a site's own uncategorised templates don't lead the list.
  scope :ordered, -> { order(Arel.sql("category IS NULL, category, name")) }
  scope :built_in, -> { where.not(template_key: nil) }
  scope :custom,   -> { where(template_key: nil) }

  before_validation :normalize_capability_keys

  def icon = self[:icon].presence || "sparkles"

  def built_in? = template_key.present?

  def capability_labels = Agents::CapabilityCatalog.labels(capability_keys)

  def cadence_label
    return "manual only" if cron.blank?

    Agent.parse_cron(cron)&.original || cron
  end

  # Attributes to seed an Agent from this template.
  #
  # `name:` is overridable because Agent names are unique: installing the
  # same template twice — one scoped to /blog, one to /docs — needs two
  # names, or the second is rejected outright.
  def to_agent_attributes(name: self.name)
    {
      name: name,
      description: description,
      icon: icon,
      instructions: instructions,
      capability_keys: Agents::CapabilityCatalog.valid_keys(capability_keys),
      preferred_model: preferred_model.presence,
      cron: cron.presence,
      template_key: template_key,
      enabled: false
    }
  end

  # Build (unsaved) the agent this template describes.
  def to_agent(name: self.name) = Agent.new(to_agent_attributes(name: name))

  # Has this template already been stood up? Only meaningful for built-ins —
  # a site's own template has no key to match on, so installing it twice is
  # a legitimate thing to do.
  def installed?
    return false unless built_in?

    Agent.exists?(template_key: template_key)
  end

  private

  def normalize_capability_keys
    self.capability_keys = Agents::CapabilityCatalog.valid_keys(capability_keys)
  end

  def validate_cron
    return if cron.blank?

    errors.add(:cron, "is not a valid cron expression") unless Agent.parse_cron(cron)
  end
end
