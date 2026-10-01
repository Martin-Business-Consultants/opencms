# frozen_string_literal: true

# The reporting snapshots, for agents and scripts.
#
# Read-only on purpose. Running a report spends money against the site's
# DataForSEO balance and is a person's decision — `reports:run` is not an
# agent capability and there is no create action here. What an agent gets is
# what has already been measured: the latest snapshot of each kind with its
# headline figures and how they moved, and any one report in full.
class Api::ReportsController < Api::BaseController
  include PluginGated
  plugin :local_marketing

  enforce_authorization

  agent_summary(:index) do |payload|
    rows = Array(payload["reports"])
    moved = rows.count { |r| Array(r["metrics"]).any? { |m| m["previous"] && m["now"] != m["previous"] } }
    "#{rows.length} reports with a snapshot; #{moved} moved since the run before."
  end
  agent_breadcrumbs(:index) do |payload|
    kinds = Array(payload["reports"]).map { |r| r["kind"] }
    [crumb("Open one in full", "cms report #{kinds.first || "<kind>"}"),
     crumb("Compare with the run before", "cms report #{kinds.first || "<kind>"} --previous"),
     crumb("What's already filed", "cms findings --status open")]
  end
  agent_summary(:show) do |payload|
    r = payload["report"] or next payload["note"]
    "#{r["kind"]} measured #{r["measured_at"]}."
  end
  agent_breadcrumbs(:show) do |payload|
    kind = payload.dig("report", "kind") || "<kind>"
    [crumb("The snapshot before, to compare", "cms report #{kind} --previous"),
     crumb("File what you found", "cms recommend <kind> <title> --body ... --impact N")]
  end

  requires_capability "reports:read", only: [:index, :show]

  def index
    latest = Report.latest_by_kind
    @reports = Reports::Catalog.all.filter_map { |definition| latest[definition.key] }
    @never_run = Reports::Catalog::KEYS - latest.keys
  end

  # /api/reports/:kind — the latest snapshot of that kind, or with
  # `?previous` the one before it.
  def show
    @kind = params[:kind].to_s
    return render json: {error: "unknown report kind", kinds: Reports::Catalog::KEYS}, status: :not_found unless Reports::Catalog.known?(@kind)

    @report = Report.latest_by_kind[@kind]
    return render :never_run, status: :not_found if @report.nil?

    if params.key?(:previous)
      @report = @report.previous
      render :no_previous if @report.nil?
    end
  end
end
