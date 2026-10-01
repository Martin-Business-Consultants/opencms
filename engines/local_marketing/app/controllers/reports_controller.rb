# frozen_string_literal: true

# Reporting — what the outside world can see about this business.
#
# The index is the catalog, not a list of rows: every report kind, with its
# most recent answer and how old it is. A report nobody has ever run still gets
# a row, because "we have never checked" is the most important thing the page
# can tell someone. Running one is Reports::RunsController.
#
# The pages say what each report measures and what it found, in words and
# tables — the charts are being rethought.
class ReportsController < ApplicationController
  include PluginGated
  plugin :local_marketing

  requires_capability "reports:read", only: [:index, :show]
  # Deleting a snapshot removes a data point from every trend built on it, so
  # it sits with running rather than with a bare read.
  requires_capability "reports:run", only: :destroy

  def index
    @range = Reports::DateRange.parse(params)
    @profile = Reports::Profile.load
    @configured = DataForSeo::Client.configured?
    @running = Report.in_flight.recent.to_a
    @catalog = catalog
    @spend = Report.spend(@range)
  end

  def show
    @report = Report.find(params[:id])
    @range = Reports::DateRange.parse(params)
    @definition = @report.definition
    @previous = @report.previous
    @metrics = @report.metrics(against: @previous)
    @history = @range.scope(Report.of_kind(@report.kind)).recent.limit(60).to_a
    @extra = @definition&.page_props || {}
    @profile = Reports::Profile.load
  end

  def destroy
    Report.find(params[:id]).remove

    redirect_to reports_path, notice: "Snapshot deleted."
  end

  private

  # One row per report kind: what it answers, what it needs, what it costs,
  # and the latest run if there is one.
  def catalog
    latest = Report.latest_by_kind
    in_flight = Report.in_flight.pluck(:kind).to_set

    Reports::Catalog.all.map do |definition|
      report = latest[definition.key]
      {
        definition: definition,
        latest: report,
        metrics: report ? report.metrics : [],
        running: in_flight.include?(definition.key),
        missing: @profile.missing(definition.requires).map(&:to_s),
        stale: report.present? && report.stale?(definition.cadence)
      }
    end
  end
end
