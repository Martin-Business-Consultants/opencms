# frozen_string_literal: true

require "local_marketing/engine"

# Local Marketing: what the outside world can see about the business. Reports
# are DataForSEO snapshots (Reports::Catalog, Report), plus the site audit of
# the live site; the Marketer's Report scores them against the business's
# targets and says what to do next. Bundled and off by default.
#
# It runs without the AI plugin: the written summaries ask for a model through
# `Cms::Plugins.provided(:ai)` and are left out when there is none. Handing a
# do-next item to an agent goes through `provided(:agents)` the same way.
#
# Its model keeps the name and table it had in the core (reports) — it
# predates plugins; a new table would be prefixed.
module LocalMarketing
  # What `Cms::Plugins.provided(:site_audit)` hands back: the latest audit's
  # verdict per managed script, for the Scripts page (Consent & Scripts).
  module SiteAudit
    module_function

    def readable_by?(user) = user&.can?("reports:read") || false
    def runnable_by?(user) = user&.can?("reports:run") || false

    def run_path = routes.run_reports_path(kind: "site_audit")

    # nil when no audit has finished yet.
    def script_statuses
      report = Report.complete.of_kind("site_audit").recent.first
      return nil if report.nil?

      rows = Array(report.data.dig("tracking", "managed"))
      {
        measured_at: report.created_at,
        path: routes.report_path(report),
        running: Report.in_flight.of_kind("site_audit").exists?,
        statuses: rows.to_h { |r| [r["id"].to_s, {status: r["status"] || "unknown", label: r["status_label"] || "Not checked"}] }
      }
    end

    def routes = Rails.application.routes.url_helpers
  end
end
