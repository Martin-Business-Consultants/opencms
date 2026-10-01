# frozen_string_literal: true

# The frontend this headless CMS serves, as far as the CMS knows it: where the
# site lives and its repo (Settings › General and › GitHub), and what its
# build last reported (POST /api/frontend/builds, sent by the Astro
# integration). Read by the Developers screen and the dashboard.
module Frontend
  SETTING = "frontend"

  module_function

  def record_build(report)
    build = report.slice("integration", "integration_version", "framework", "framework_version", "site_url")
      .transform_values { it.to_s.first(100) }.compact_blank
    build["pages"] = report["pages"].to_i if report["pages"].present?
    build["duration_ms"] = report["duration_ms"].to_i if report["duration_ms"].present?
    build["built_at"] = Time.current.iso8601
    Setting.set(SETTING, {"last_build" => build})
    Event.record("frontend.built", **build.symbolize_keys.except(:built_at))
    build
  end

  # {integration:, integration_version:, framework:, framework_version:,
  #  pages:, built_at: Time, …} or nil when no build has reported.
  def last_build
    build = Setting.get(SETTING)["last_build"]
    return nil unless build.is_a?(Hash) && build["built_at"].present?

    build.symbolize_keys.merge(built_at: Time.zone.parse(build["built_at"]))
  end

  def connected? = last_build.present?

  def site_url = Setting.get("general")["site_base_url"].presence

  def repo = Setting.get("github")["frontend_github_repo"].presence

  # The tokens that used the API lately — people's (the CLI, MCP, scripts)
  # and service tokens (the site's build, jobs) — newest first, for the
  # dashboard: this CMS is mostly driven through them.
  # [{name:, kind: "personal" | "service", last_used_at:}, …]
  def recent_api_use(since: 7.days.ago, limit: 6)
    people = ApiToken.includes(:user).where(last_used_at: since..).map do |token|
      {name: token.user&.name.presence || token.user&.email || "Someone", kind: "personal", last_used_at: token.last_used_at}
    end
    services = ServiceToken.active.where(last_used_at: since..).map do |token|
      {name: token.name, kind: "service", last_used_at: token.last_used_at}
    end
    (people + services).sort_by { -it[:last_used_at].to_i }.first(limit)
  end
end
