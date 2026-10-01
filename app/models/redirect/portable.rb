# frozen_string_literal: true

require "csv"

# Redirect rules in and out as CSV, one rule per row. The admin's Import/Export
# buttons and `cms redirects import|export` share the format, so what one
# exports the other accepts.
module Redirect::Portable
  extend ActiveSupport::Concern

  CSV_COLUMNS = %w[source_path destination_url status_code active notes].freeze

  class_methods do
    def to_csv
      CSV.generate do |csv|
        csv << CSV_COLUMNS
        ordered.each { |redirect| csv << redirect.to_csv_row }
      end
    end

    def csv_filename
      "redirects-#{Site.key}-#{Time.current.strftime("%Y%m%d")}.csv"
    end

    # Upserts by source path, so re-running an import is a no-op rather than a
    # pile of duplicates. Raises CSV::MalformedCSVError on unparseable input.
    def import_csv(text)
      Redirect::Import.new(text).tap(&:run)
    end
  end

  def to_csv_row
    [source_path, destination_url, status_code, active ? "true" : "false", notes]
  end
end
