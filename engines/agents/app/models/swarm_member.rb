# frozen_string_literal: true

# One seat in a swarm: which agent, at what cadence, on which model.
#
# Cadence here is determinate (this weekday at this hour), not an interval,
# because a roster is a rota — "Mon 09:00 metadata, Wed 09:00 links" is
# something a person can reason about, and "every 168 hours from whenever it
# last ran" drifts until two agents that were meant to be a day apart collide.
class SwarmMember < ApplicationRecord
  FREQUENCIES = %w[daily weekly monthly].freeze
  # Index 1-7, ISO: Monday is 1. Index 0 is a placeholder so `DAYS[day]`
  # reads correctly without an off-by-one at every call site.
  ISO_DAYS = %w[— Mon Tue Wed Thu Fri Sat Sun].freeze

  belongs_to :swarm, inverse_of: :swarm_members
  belongs_to :agent

  has_many :agent_runs, dependent: :nullify

  validates :agent_id, uniqueness: {scope: :swarm_id, message: "is already in this swarm"}
  validates :frequency, inclusion: {in: FREQUENCIES}
  validates :hour, inclusion: {in: 0..23}
  validate  :validate_day_for_frequency

  scope :ordered, -> { order(:position) }
  scope :enabled, -> { where(enabled: true) }

  def display_name = role.presence || agent&.name || "(removed agent)"

  # A tier, not a model id. A seat that named "opus" went on naming it after
  # the provider changed underneath it — configured-looking, and resolving to
  # nothing.
  def resolved_tier = Ai::Models.tier_of(model.presence || agent&.preferred_model)

  def resolved_model = Ai::Models.resolve(model.presence || agent&.preferred_model)

  def schedule_label
    at = format("%02d:00", hour.to_i)
    case frequency
    when "daily"   then "Daily · #{at}"
    when "weekly"  then "#{ISO_DAYS[day.to_i] || "—"} · #{at}"
    when "monthly" then "Day #{day} · #{at}"
    end
  end

  # Due when the rota matches this hour and we haven't already fired this
  # occurrence. Comparing against the start of the hour (rather than "an hour
  # ago") is what makes it fire once per slot however often the scheduler
  # wakes up.
  def due?(now = Time.current)
    return false unless enabled?
    return false unless agent
    return false if matches_time?(now) == false

    last_enqueued_at.nil? || last_enqueued_at < now.beginning_of_hour
  end

  def dispatch!(trigger: "swarm", triggered_by: nil)
    return nil unless agent

    agent.dispatch!(
      trigger: trigger,
      triggered_by: triggered_by,
      swarm: swarm,
      swarm_member: self
    )
  end

  def mark_enqueued!(at: Time.current)
    update!(last_enqueued_at: at)
  end

  private

  def matches_time?(now)
    return false unless hour.to_i == now.hour

    case frequency
    when "daily"   then true
    when "weekly"  then day.to_i == iso_wday(now)
    when "monthly" then day.to_i == now.day
    else false
    end
  end

  # Monday=1 … Sunday=7. Ruby's `wday` is Sunday=0, which would make Sunday
  # unreachable against an ISO day column.
  def iso_wday(now) = now.wday.zero? ? 7 : now.wday

  # A monthly seat on day 31 silently never fires in February. Capping at 28
  # is the only bound that behaves the same every month.
  def validate_day_for_frequency
    case frequency
    when "weekly"
      errors.add(:day, "must be 1 (Mon) – 7 (Sun)") unless (1..7).cover?(day.to_i)
    when "monthly"
      errors.add(:day, "must be 1–28, so it fires every month") unless (1..28).cover?(day.to_i)
    end
  end
end
