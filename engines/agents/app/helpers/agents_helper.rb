# frozen_string_literal: true

module AgentsHelper
  RUN_TONES = {"completed" => "Done", "failed" => "Failed", "canceled" => "Canceled", "expired" => "Expired",
               "queued" => "Queued", "claimed" => "Claimed", "running" => "Running"}.freeze

  SCOPE_KIND_LABELS = {"site" => "The whole site", "collection" => "A collection", "path_prefix" => "Pages under a path",
                       "locale" => "One locale"}.freeze

  def run_status_tag(run)
    label = run.stopping? ? "Stopping" : RUN_TONES.fetch(run.status, run.status.humanize)
    status_tag label, highlight: run.active?
  end

  # "4m 12s" for a run that took that long; "—" before it has finished.
  def run_duration(seconds)
    return "—" if seconds.nil?
    return "#{seconds}s" if seconds < 60

    minutes, secs = seconds.divmod(60)
    minutes < 60 ? "#{minutes}m #{secs}s" : "#{minutes / 60}h #{minutes % 60}m"
  end

  def scope_kind_options = ContentScope::KINDS.map { [SCOPE_KIND_LABELS.fetch(it, it.humanize), it] }

  # The tier choices plus the concrete models, for an agent or a seat.
  def model_preference_options
    tiers = Ai::Models.tier_options.map { [it[:label], it[:value]] }
    models = Ai::Models.all.map { |id, spec| ["#{spec[:name]} (#{id})", id] }
    [["Default tier", ""]] + tiers + models
  end

  # A step of a run's transcript as one line: when, what kind, what it said.
  def transcript_line(step)
    return step.to_s unless step.is_a?(Hash)

    (step["text"] || step["message"] || step["summary"] || step["detail"] || step.except("at", "kind", "type").to_json).to_s
  end
end
