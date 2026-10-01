# frozen_string_literal: true

require "csv"

# Tools › Redirects › Import: upserts rules from a CSV in the export's format.
class Tools::Redirects::ImportsController < ApplicationController
  requires_capability "redirects:write", only: :create

  def create
    file = params[:file]

    if file.respond_to?(:read)
      import = Redirect.import_csv(file.read)
      Redirect.track_event(:imported, created: import.created, updated: import.updated, errored: import.errored)
      redirect_to tools_redirects_path, notice: import.summary
    else
      redirect_to tools_redirects_path, alert: "Pick a CSV file."
    end
  rescue CSV::MalformedCSVError => e
    redirect_to tools_redirects_path, alert: "CSV parse error: #{e.message}"
  end
end
