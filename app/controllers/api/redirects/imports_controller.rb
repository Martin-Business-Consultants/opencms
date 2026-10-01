# frozen_string_literal: true

require "csv"

# POST /api/redirects/import — accepts the CSV as a raw request body or as an
# uploaded `file` param, so `cms redirects import < redirects.csv` works as well
# as a multipart post. Upserts by source path (Redirect::Import).
class Api::Redirects::ImportsController < Api::BaseController
  def create
    require_capability!("redirects:write")

    csv = uploaded_csv
    if csv.blank?
      render json: {error: "invalid", message: "No CSV supplied"}, status: :unprocessable_content
    else
      @import = Redirect.import_csv(csv)
      Redirect.track_event(:imported, created: @import.created, updated: @import.updated, errored: @import.errored)
    end
  rescue CSV::MalformedCSVError => e
    render json: {error: "invalid_csv", message: e.message}, status: :unprocessable_content
  end

  private

  def uploaded_csv
    file = params[:file]
    return file.read if file.respond_to?(:read)

    request.body.rewind
    request.body.read
  end
end
