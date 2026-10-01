# frozen_string_literal: true

# Queuing a report and running it.
#
# `Report.queue` is the one way a report gets queued. Three callers — the Run
# button, the weekly refresh, and the baseline a marketer presses once — used
# to each hold a copy of the same guards, and a guard that lives in three
# places is a guard that is wrong in one. Every run spends money, so the
# guards matter: no credential, no queue; inputs missing, no queue; already
# running, no second charge.
#
# `run_now` executes one queued report against DataForSEO, in the background
# (Report::RunJob) because the calls are slow enough to time out a request —
# LLM mentions is documented at up to 120 seconds, and Local rankings makes
# one SERP call per tracked keyword. No retries: a transient failure retried
# three times is three charges for one report. A failed report says why and
# waits for someone to press the button again.
module Report::Runnable
  extend ActiveSupport::Concern

  Queued = Struct.new(:report, :error, :skipped, keyword_init: true) do
    def queued? = report.present?
    def skipped? = skipped.present?
  end

  class_methods do
    def queue(kind, requested_by: nil, profile: Reports::Profile.load)
      definition = Reports::Catalog.definition_class(kind)
      return Queued.new(error: "Unknown report: #{kind}") if definition.nil?
      return Queued.new(error: "Add your DataForSEO credentials before running a report.") unless DataForSeo::Client.configured?

      missing = profile.missing(definition.requires)
      if missing.any?
        return Queued.new(error: "#{definition.title} needs #{missing.map { |f| f.to_s.humanize.downcase }.to_sentence} first.")
      end

      if (existing = in_flight.of_kind(kind).first)
        return Queued.new(report: existing, skipped: "already running")
      end

      report = create!(kind: kind, requested_by: requested_by, params: profile.to_h)
      report.run_later
      # Recorded here, not by whoever asked, so a baseline, a setup and the
      # weekly refresh are in the audit log as well as the Run button.
      report.track_event(:queued, kind: kind)
      Queued.new(report: report)
    end

    # [[kind, Queued], …] for several kinds at once, against one profile.
    def queue_all(kinds, requested_by: nil, profile: Reports::Profile.load)
      kinds.map { |kind| [kind, queue(kind, requested_by: requested_by, profile: profile)] }
    end

    # Every report the profile can run right now, in catalog order — what
    # "run the baseline" means when a template hasn't narrowed it.
    def runnable_kinds(profile = Reports::Profile.load)
      Reports::Catalog.all.select { |d| profile.missing(d.requires).empty? }.map(&:key)
    end
  end

  def run_later
    Report::RunJob.perform_later(id)
  end

  def run_now
    # Guards against a double-dispatch (button pressed twice, job retried by
    # the adapter) spending twice.
    return unless queued?

    running!
    measure
  end

  def running!(at: Time.current)
    update!(status: "running", started_at: at)
  end

  def complete!(data:, cost:)
    update!(status: "complete", data: data, cost: cost, error: nil, completed_at: Time.current)
  end

  # The message is what the person sees, so it is truncated rather than
  # allowed to be a page of backtrace, and the status is set even when the
  # write of `data` would have failed — a report that fails must not stay
  # "running" forever and block the next run.
  def fail!(message)
    update!(status: "failed", error: message.to_s.truncate(2_000), completed_at: Time.current)
  end

  private

  def measure
    measurement = Reports::Catalog.fetch(kind, profile: Reports::Profile.load, client: DataForSeo::Client.from_settings)

    data = measurement.call
    # Non-numeric things the reader should know — a refused field, a
    # secondary call that failed — ride along on the snapshot.
    data = data.merge(warnings: measurement.warnings) if measurement.warnings.any?
    complete!(data: data, cost: measurement.cost)

    track_event(:completed, actor: requested_by, kind: kind, cost: measurement.cost.round(4))
  rescue DataForSeo::NotConfigured, DataForSeo::Error => e
    fail!(e.message)
  rescue StandardError => e
    # The message reaches a person in the UI, so it names the report rather
    # than leaking a bare NoMethodError with no context.
    Rails.logger.error("[Report::RunJob] #{kind} failed: #{e.class}: #{e.message}")
    fail!("#{title} failed: #{e.message}")
  end
end
