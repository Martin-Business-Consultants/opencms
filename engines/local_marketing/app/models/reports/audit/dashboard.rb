# frozen_string_literal: true

module Reports
  module Audit
    # The dashboard's card: the latest audit's open findings, what they'd
    # fix, and whether one is running. One query for the snapshot, one for
    # the in-flight check, and nothing that costs money.
    module Dashboard
      LIMIT = 8

      module_function

      def payload(user)
        return nil unless user&.can?("reports:read")

        report = Report.complete.of_kind("site_audit").recent.first
        running = Report.in_flight.of_kind("site_audit").exists?
        profile = Reports::Profile.load
        missing = profile.missing(Definitions::SiteAudit.requires).map(&:to_s)

        base = {
          can_run: user.can?("reports:run"),
          configured: DataForSeo::Client.configured?,
          missing: missing,
          running: running,
          run_path: "/reports/site_audit/run"
        }
        return base.merge(report: nil) if report.nil?

        findings = Array(report.data["findings"]).map(&:with_indifferent_access)
        open = Dismissals.open(findings)
        base.merge(
          report: {
            id: report.id, measured_at: report.created_at.iso8601, base_url: report.data["base_url"],
            counts: open.group_by { |f| f[:severity] }.transform_values(&:length),
            open: open.length, dismissed: findings.length - open.length,
            passed: Array(report.data["passed"]).length,
            findings: open.first(LIMIT),
            narrative: report.data["narrative"]
          }
        )
      end
    end
  end
end
