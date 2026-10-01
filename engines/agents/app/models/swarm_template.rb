# frozen_string_literal: true

# A reusable swarm blueprint: a name and a roster.
#
# Members name an agent TEMPLATE, not an agent row. A swarm template has to
# be standable-up on a site that has never created an agent, so
# instantiating one creates the agents it needs (from their templates) and
# then seats them. Naming agent rows instead would make every template
# useless until someone had already built its roster by hand — which is the
# work the template exists to save.
class SwarmTemplate < ApplicationRecord
  has_many :content_scopes, as: :scopable, dependent: :destroy

  validates :name, presence: true, uniqueness: true, length: {maximum: 120}
  validates :template_key, uniqueness: true, allow_nil: true
  validate  :validate_members

  scope :ordered, -> { order(Arel.sql("category IS NULL, category, name")) }
  scope :built_in, -> { where.not(template_key: nil) }
  scope :custom,   -> { where(template_key: nil) }

  def icon = self[:icon].presence || "users"

  def built_in? = template_key.present?

  # Roster rows normalized to symbol keys with defaults filled in, so no
  # caller has to guess whether a key is present or which case it's in.
  def member_rows
    Array(members).filter_map do |row|
      row = row.symbolize_keys
      key = row[:agent_template_key].presence
      next if key.blank?

      {
        agent_template_key: key.to_s,
        role: row[:role].presence,
        model: row[:model].presence,
        frequency: row[:frequency].presence || "weekly",
        day: (row[:day] || 1).to_i,
        hour: (row[:hour] || 9).to_i
      }
    end
  end

  # Templates this roster names that don't exist here. A swarm template can
  # outlive an agent template it references, and a swarm built from it would
  # otherwise be silently short a member.
  def missing_template_keys
    keys = member_rows.map { |row| row[:agent_template_key] }
    return [] if keys.empty?

    keys - AgentTemplate.where(template_key: keys).pluck(:template_key)
  end

  def installed?
    return false unless built_in?

    Swarm.exists?(template_key: template_key)
  end

  # Create the swarm this template describes, plus any agents its roster
  # needs that don't exist yet. Disabled, like every instantiated thing here:
  # standing up a team should never start it working.
  #
  # Returns the persisted Swarm, or raises ActiveRecord::RecordInvalid.
  def instantiate!(name: self.name)
    swarm = nil
    transaction do
      swarm = Swarm.create!(
        name: name,
        description: description,
        icon: icon,
        enabled: false,
        template_key: template_key
      )

      member_rows.each_with_index do |row, index|
        agent = agent_for(row[:agent_template_key])
        next unless agent

        swarm.swarm_members.create!(
          agent: agent,
          role: row[:role],
          model: row[:model],
          frequency: row[:frequency],
          day: row[:day],
          hour: row[:hour],
          position: index,
          enabled: true
        )
      end
    end
    swarm
  end

  private

  # Reuse an agent already built from this template rather than creating a
  # second copy — two agents with the same instructions on the same site is a
  # duplicate-work bug that reads as a full roster.
  def agent_for(template_key)
    existing = Agent.find_by(template_key: template_key)
    return existing if existing

    template = AgentTemplate.find_by(template_key: template_key)
    return nil unless template

    Agent.create!(template.to_agent_attributes)
  end

  def validate_members
    return errors.add(:members, "must list at least one agent") if member_rows.empty?

    bad = member_rows.reject { |row| SwarmMember::FREQUENCIES.include?(row[:frequency]) }
    errors.add(:members, "have an unknown frequency: #{bad.map { |r| r[:frequency] }.uniq.join(", ")}") if bad.any?
  end
end
