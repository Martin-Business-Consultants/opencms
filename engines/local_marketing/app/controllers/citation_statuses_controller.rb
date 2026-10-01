# frozen_string_literal: true

# What a person has done about a citation directory (Reports::CitationStatuses).
class CitationStatusesController < ApplicationController
  include PluginGated
  plugin :local_marketing

  # Managing citations is work on the business's behalf, like running a
  # report is spending on it — same capability.
  requires_capability "reports:run", only: [:update]

  def update
    directory = params[:directory].to_s.downcase.strip
    return redirect_back fallback_location: reports_path, alert: "Unknown directory." if directory.blank?

    status = params[:status].to_s
    return redirect_back fallback_location: reports_path, alert: "Unknown status." unless Reports::CitationStatuses.known_status?(status)

    Reports::CitationStatuses.update(directory, status: status, note: params[:note], by: Current.user)
    redirect_back fallback_location: reports_path, notice: "#{directory}: #{status.humanize.downcase}"
  end
end
