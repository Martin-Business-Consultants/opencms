# frozen_string_literal: true

# Running a report: queues a job and redirects. The calls take up to two
# minutes and cost money, so they can't happen during a render, and the row
# exists as `queued` before the browser comes back — a refresh shows it
# running rather than charging twice.
class Reports::RunsController < ApplicationController
  include PluginGated
  plugin :local_marketing

  requires_capability "reports:run", only: :create

  def create
    kind = params[:kind].to_s
    result = Report.queue(kind, requested_by: Current.user)

    if result.error
      # Credentials and inputs are fixed in one place; send them there.
      target = Reports::Catalog.known?(kind) ? settings_reporting_path : reports_path
      redirect_to target, alert: result.error
    elsif result.skipped?
      redirect_to report_path(result.report), notice: "That report is already running."
    else
      redirect_to report_path(result.report), notice: "Running #{result.report.title}…"
    end
  end
end
