# frozen_string_literal: true

# One execution of an agent, performed by a local harness.
#
# The server queues work and records what came back; it never runs a model.
# That inverts the staleness rule a server-executed queue would use. When
# Solid Queue is the executor it is up whenever the app is, so a run sitting
# in `pending` means something broke. Here the executor is a worker box that
# can reboot, be rebuilt, or simply not be running yet — a `queued` run with
# no worker is WAITING, and reaping it would fail work nobody has attempted.
#
# So only a CLAIMED run whose lease lapsed is stale, and it goes back to
# `queued` with `attempts += 1` rather than failing. A worker that dies
# mid-run costs one retry, not one lost run.
class AgentRun < ApplicationRecord
  include Eventable
  include Executable

  STATUSES = %w[queued claimed running completed failed canceled expired].freeze
  ACTIVE_STATUSES = %w[queued claimed running].freeze
  TERMINAL_STATUSES = %w[completed failed canceled expired].freeze
  TRIGGERS = %w[manual schedule swarm api].freeze

  # How long a claim is good for. Short enough that a dead worker's run is
  # back in the queue quickly; long enough that a working one isn't stolen
  # mid-task. Workers extend it with a heartbeat.
  DEFAULT_LEASE = 10.minutes
  # A run nobody claims for this long is almost always a worker that never
  # came back, and running it now would act on a site that has since moved.
  DEFAULT_TTL = 24.hours
  # After this many lease losses, stop requeuing: something about this run
  # kills whatever picks it up, and an infinite retry hides that.
  MAX_ATTEMPTS = 3
  # Transcript entries are unbounded input from a worker; a runaway loop
  # shouldn't be able to grow one row without limit.
  MAX_TRANSCRIPT_STEPS = 500

  belongs_to :agent,        optional: true
  belongs_to :swarm,        optional: true
  belongs_to :swarm_member, optional: true
  belongs_to :triggered_by, class_name: "User", optional: true

  has_many :recommendations, dependent: :nullify
  has_many :revisions, dependent: :nullify

  validates :agent_name, presence: true
  validates :status,  inclusion: {in: STATUSES}
  validates :trigger, inclusion: {in: TRIGGERS}

  scope :recent,   -> { order(created_at: :desc) }
  scope :active,   -> { where(status: ACTIVE_STATUSES) }
  scope :finished, -> { where(status: TERMINAL_STATUSES) }
  scope :for_swarm, ->(swarm) { where(swarm: swarm) }

  # The claim queue: highest priority first, then oldest. Expired runs are
  # excluded here rather than only being swept, so a backlogged queue can't
  # hand a worker day-old work in the window before the reaper runs.
  scope :claimable, ->(now = Time.current) {
    where(status: "queued")
      .where("expires_at IS NULL OR expires_at > ?", now)
      .order(priority: :desc, created_at: :asc)
  }

  STATUSES.each { |state| define_method("#{state}?") { status == state } }

  def active?   = ACTIVE_STATUSES.include?(status)
  def finished? = TERMINAL_STATUSES.include?(status)

  # Winding down after someone pressed Stop but before the worker noticed.
  def stopping? = cancel_requested? && ACTIVE_STATUSES.include?(status)

  # What it cost, priced at the model stamped in its own brief — never at
  # today's tier (the same rule Agents::Spend follows).
  def cost
    Ai::Pricing.usd(Ai::Pricing.cost_cents(model: brief&.dig("agent", "preferred_model"),
      input_tokens: input_tokens, output_tokens: output_tokens))
  end

  def duration_seconds
    return nil unless started_at && finished_at

    (finished_at - started_at).round
  end

  # --- the worker protocol -------------------------------------------------

  # Hand the next run to a worker. A conditional UPDATE keyed on the current
  # status is what makes this safe: two workers polling at the same moment
  # both see the same candidate, and only the one whose UPDATE matched a row
  # gets it. Walks a few candidates so the loser retries the next run rather
  # than coming back empty while work is waiting.
  def self.claim!(worker:, lease: DEFAULT_LEASE, now: Time.current)
    claimable(now).limit(5).each do |candidate|
      won = where(id: candidate.id, status: "queued").update_all(
        status: "claimed",
        claimed_by: worker.to_s,
        claimed_at: now,
        lease_expires_at: now + lease,
        attempts: candidate.attempts + 1,
        updated_at: now
      )
      return candidate.reload if won == 1
    end
    nil
  end

  # The worker has started work. Separate from claiming so a run that is
  # claimed but never started is distinguishable from one genuinely underway.
  def start!(lease: DEFAULT_LEASE, now: Time.current)
    transition(from: %w[claimed], to: "running", started_at: now, lease_expires_at: now + lease)
  end

  # Extend the lease. Returns false once the run is no longer the worker's to
  # extend — reaped, canceled, or finished — which is the signal for the
  # worker to stop rather than keep burning tokens on work that was requeued.
  def heartbeat!(lease: DEFAULT_LEASE, now: Time.current)
    transition(from: %w[claimed running], to: status, lease_expires_at: now + lease)
  end

  # Append a progress step. Kept append-only and capped: it exists so a run
  # in flight is legible without the worker holding a connection open.
  def report!(step)
    return false unless active?

    entry = {"at" => Time.current.iso8601}.merge(step.to_h.stringify_keys)
    steps = Array(transcript)
    steps = steps.last(MAX_TRANSCRIPT_STEPS - 1) if steps.length >= MAX_TRANSCRIPT_STEPS
    update!(transcript: steps + [entry])
  end

  def complete!(summary: nil, input_tokens: nil, output_tokens: nil, now: Time.current)
    transition(
      from: %w[claimed running], to: "completed",
      summary: summary.presence, finished_at: now,
      input_tokens: input_tokens, output_tokens: output_tokens
    ).tap { |won| touch_agent_last_run(now) if won }
  end

  def fail!(error:, summary: nil, now: Time.current)
    transition(
      from: %w[claimed running], to: "failed",
      error: error.to_s.truncate(5_000), summary: summary.presence, finished_at: now
    ).tap { |won| touch_agent_last_run(now) if won }
  end

  # Stop a run. Queued work dies immediately; claimed/running work gets the
  # flag and the worker is told at its next heartbeat. A second request on an
  # already-stopping run forces it down — the escape hatch for a worker that
  # is gone and will never read the flag.
  def request_cancel!(now: Time.current)
    if queued?
      transition(from: %w[queued], to: "canceled", finished_at: now)
    elsif stopping?
      transition(from: ACTIVE_STATUSES, to: "canceled", finished_at: now)
    else
      self.class.where(id: id, status: ACTIVE_STATUSES).update_all(cancel_requested: true, updated_at: Time.current)
      reload
      true
    end
  end

  # --- reaping -------------------------------------------------------------

  # Claimed/running runs whose lease has lapsed. Deliberately does NOT match
  # `queued` — see the class comment.
  scope :lease_expired, ->(now = Time.current) {
    where(status: %w[claimed running]).where(lease_expires_at: ...now)
  }

  scope :past_expiry, ->(now = Time.current) {
    where(status: "queued").where.not(expires_at: nil).where(expires_at: ...now)
  }

  # Requeue abandoned runs and drop ones nobody claimed in time. Returns a
  # count per outcome so the job can log something meaningful.
  def self.reap!(now: Time.current)
    requeued = failed = expired = 0

    lease_expired(now).find_each do |run|
      if run.attempts >= MAX_ATTEMPTS
        failed += 1 if run.transition(
          from: %w[claimed running], to: "failed", finished_at: now,
          error: "Abandoned by #{run.claimed_by || "a worker"} after #{run.attempts} attempts — " \
                 "the lease expired with no heartbeat each time."
        )
      elsif run.transition(from: %w[claimed running], to: "queued",
        claimed_by: nil, claimed_at: nil, lease_expires_at: nil, started_at: nil)
        requeued += 1
      end
    end

    past_expiry(now).find_each do |run|
      expired += 1 if run.transition(
        from: %w[queued], to: "expired", finished_at: now,
        error: "Expired unclaimed after #{(DEFAULT_TTL / 3600).to_i}h — no worker picked it up."
      )
    end

    {requeued: requeued, failed: failed, expired: expired}
  end

  # Atomic, conditional status transition — a single UPDATE keyed on the
  # current status, so two writers (a worker completing, a reaper requeuing)
  # can't both win. Returns true only for the one that changed the row.
  #
  # Attributes are written as given, nils included. Compacting them here
  # would look tidy and quietly break requeuing: releasing a lease IS
  # writing nil to claimed_by/claimed_at/lease_expires_at, and a "helpful"
  # compact drops exactly those, leaving a requeued run still stamped with
  # the worker that abandoned it.
  def transition(from:, to:, **attributes)
    changed = self.class.unscoped.where(id: id, status: Array(from))
      .update_all(attributes.merge(status: to, updated_at: Time.current))
    return false unless changed == 1

    reload
    true
  end

  private

  # `last_run_at` drives "when did this agent last actually do something",
  # which is a different question from when it was last queued.
  def touch_agent_last_run(now)
    agent&.update_columns(last_run_at: now, updated_at: now)
  end
end
