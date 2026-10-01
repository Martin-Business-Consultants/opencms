# frozen_string_literal: true

# How this install asks the public site to rebuild. A provider knows whether
# it's configured and how to fire one build; this module owns the debounce
# and the rolling log, whichever provider is in use.
#
#   Deploys.current             # the provider Settings › Deploy picked
#   Deploys.current.configured?
#   Deploys.schedule_later(reason: "page.published")  # debounced, after content changes
#   Deploys.trigger_later                               # now, from "Deploy now"
#
# Content changes arrive in bursts, so schedule_later stamps the setting's
# `scheduled_at` and enqueues Deploys::TriggerJob after DEBOUNCE_WINDOW; the
# job's trigger_now skips if a newer enqueue has overwritten the stamp, so
# one build fires per burst.
#
# Two ship with the core: a build hook (POST to a URL — Cloudflare Pages,
# Vercel, Netlify, any CI) and GitHub (a repository_dispatch on the site's
# repo, Settings › GitHub). A plugin adds more with
# `Cms::Plugins.deploy_provider`.
#
# Which one: the `provider` stored in the deploy setting, else the build hook
# when a hook URL is set — every install that deployed before providers
# existed — else GitHub.
module Deploys
  SETTING_KEY     = "deploy"
  DEBOUNCE_WINDOW = 60.seconds
  STATUSES        = %w[scheduled success failure disabled skipped].freeze
  MAX_LOG_SIZE    = 20

  Attempt = Struct.new(:status, :http_status, :error, keyword_init: true)

  CORE_PROVIDERS = {
    "build_hook" => "Deploys::BuildHook",
    "github"     => "Deploys::Github"
  }.freeze

  module_function

  # {"build_hook" => Deploys::BuildHook, …}, the core's and enabled plugins'.
  def providers
    CORE_PROVIDERS.transform_values(&:constantize).merge(Cms::Plugins.enabled_deploy_providers)
  end

  def current(config = Setting.get(SETTING_KEY))
    providers.fetch(config["provider"].to_s) { default_for(config) }.new(config)
  end

  def default_for(config)
    config["url"].to_s.start_with?("http") ? Deploys::BuildHook : Deploys::Github
  end

  def config = Setting.get(SETTING_KEY)

  # Settings › Deploy's form and PATCH /api/deploy: a provider only if one by
  # that name exists, `paused` as a boolean. Returns what was saved.
  def configure(attributes)
    incoming = attributes.to_h.stringify_keys
    incoming["paused"] = ActiveModel::Type::Boolean.new.cast(incoming["paused"]) if incoming.key?("paused")
    incoming.delete("provider") unless providers.key?(incoming["provider"].to_s)
    Setting.set(SETTING_KEY, incoming)
    Event.record("settings.deploy_updated", url_set: incoming["url"].to_s.length.positive?, paused: incoming["paused"] == true, provider: incoming["provider"])
    incoming
  end

  def paused?(settings = config) = settings["paused"] == true

  # After a content change, batched with whatever else lands in the window.
  def schedule_later(reason:)
    settings = config
    return unless current(settings).configured?
    return if paused?(settings)

    scheduled_at = stamp_schedule(reason)
    Deploys::TriggerJob.set(wait: DEBOUNCE_WINDOW).perform_later(scheduled_at, reason)
  end

  # "Deploy now": no debounce, since a manual trigger means now. The job and
  # the stamp share one timestamp, or trigger_now would see a newer schedule
  # and skip.
  def trigger_later(reason: "manual")
    scheduled_at = stamp_schedule(reason)
    Deploys::TriggerJob.set(wait: 0.seconds).perform_later(scheduled_at, reason)
  end

  # Fires the build unless a newer schedule superseded this one, and logs the
  # attempt either way it runs.
  def trigger_now(scheduled_at, reason)
    settings = config
    return if settings["scheduled_at"] != scheduled_at

    provider = current(settings)
    if !provider.configured? || paused?(settings)
      record_attempt(status: "disabled", reason: reason, http_status: nil, error: nil)
    else
      started = monotonic_ms
      attempt = provider.fire(reason: reason)
      record_attempt(status: attempt.status, reason: reason, http_status: attempt.http_status,
        error: attempt.error, duration_ms: monotonic_ms - started)
    end
  end

  def stamp_schedule(reason)
    Time.current.iso8601(6).tap { |at| Setting.set(SETTING_KEY, {"scheduled_at" => at, "last_reason" => reason}) }
  end

  def record_attempt(status:, reason:, http_status:, error:, duration_ms: nil)
    log = Array(config["log"])
    log.unshift({
      "at"          => Time.current.iso8601,
      "status"      => status,
      "reason"      => reason,
      "http_status" => http_status,
      "error"       => error,
      "duration_ms" => duration_ms
    })

    Setting.set(SETTING_KEY, {
      "log"           => log.first(MAX_LOG_SIZE),
      "last_status"   => status,
      "last_fired_at" => Time.current.iso8601,
      "scheduled_at"  => nil
    })
  end

  def monotonic_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
end
