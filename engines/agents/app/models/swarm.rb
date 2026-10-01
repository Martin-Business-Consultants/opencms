# frozen_string_literal: true

# A standing team of agents working the site on a determinate rota, each
# member with its own cadence and model.
#
# A swarm is not a bigger agent. The reason it exists is that SEO work
# decomposes into jobs with different rhythms — a metadata sweep is weekly
# and cheap, a content-gap study is monthly and expensive, a broken-link
# crawl is nightly — and running them as one agent means either doing the
# cheap work monthly or the expensive work nightly.
class Swarm < ApplicationRecord
  include ScopableContent
  include Eventable

  has_many :swarm_members, -> { order(:position) }, dependent: :destroy, inverse_of: :swarm
  has_many :agents, through: :swarm_members
  has_many :agent_runs, dependent: :nullify

  validates :name, presence: true, uniqueness: true, length: {maximum: 120}
  validates :description, length: {maximum: 2_000}, allow_blank: true

  scope :ordered, -> { order(:name) }
  scope :enabled, -> { where(enabled: true) }

  # allow_destroy lets the edit form remove a seat via `_destroy`; reject_if
  # drops a NEW row with no agent (a stray "add member" click) but never an
  # existing one, which may be updated or destroyed without resubmitting its
  # agent_id.
  accepts_nested_attributes_for :swarm_members, allow_destroy: true,
    reject_if: ->(attrs) { attrs["id"].blank? && attrs["agent_id"].blank? }

  def icon = self[:icon].presence || "users"

  def built_in? = template_key.present?

  # Seats that would fire at `now`. A disabled swarm has none — the swarm's
  # own switch has to beat its members', or disabling one would leave its
  # rota running.
  def due_members(now = Time.current)
    return [] unless enabled?

    swarm_members.includes(:agent).select { |member| member.due?(now) }
  end

  # Queue a run for every seat due now. Returns the runs created.
  #
  # The member's rota is advanced, not the agent's own schedule: the same
  # agent can sit in a swarm and carry a personal cadence, and firing one
  # must not silently satisfy the other.
  # The scheduler's swarm half (Agent::ScheduleJob): each enabled swarm's
  # seats whose rota has come round.
  def self.dispatch_all_due(now = Time.current)
    enabled.includes(swarm_members: :agent).find_each { |swarm| swarm.dispatch_due!(now) }
  end

  def dispatch_due!(now = Time.current)
    due_members(now).filter_map do |member|
      run = member.dispatch!(trigger: "swarm")
      member.mark_enqueued!(at: now)
      run
    end
  end

  # Run the whole roster now, regardless of rota. What the "Run now" button
  # does — a person is waiting, so enabled-ness of the swarm doesn't gate it,
  # only the seat's own switch. A seat that queued a run is marked as the
  # rota marks it, so "Last queued" says so (and the rota counts it for this
  # hour rather than running the seat twice).
  def dispatch_all!(triggered_by: nil, now: Time.current)
    swarm_members.includes(:agent).select(&:enabled?).filter_map do |member|
      member.dispatch!(trigger: "manual", triggered_by: triggered_by)&.tap { member.mark_enqueued!(at: now) }
    end
  end

  def last_run_at = agent_runs.maximum(:created_at)

  def active_run_count = agent_runs.active.count
end
