# frozen_string_literal: true

require "csv"

# One CSV import (Redirect.import_csv): what it created, updated, and couldn't
# save, row by row. Row numbers count the header, so they match the line a
# person sees in a spreadsheet.
class Redirect::Import
  attr_reader :created, :updated, :errors

  def initialize(text)
    @text    = text
    @created = 0
    @updated = 0
    @errors  = []
  end

  def run
    CSV.parse(@text, headers: true).each_with_index do |row, index|
      import_row(row, line: index + 2)
    end
  end

  def errored
    errors.size
  end

  # "Import: 3 created, 1 updated, 1 errored — row 4: Source path …"
  def summary
    text = "Import: #{created} created, #{updated} updated"
    text += ", #{errored} errored" if errored.positive?
    text += " — #{errors.first(3).map { |e| "row #{e[:row]}: #{e[:errors].join("; ")}" }.join(" · ")}" if errors.any?
    text
  end

  private

  def import_row(row, line:)
    redirect = Redirect.find_or_initialize_by(source_path: Redirect.normalize_path(row["source_path"].to_s))
    existed  = redirect.persisted?
    redirect.assign_attributes(
      source_path:     row["source_path"],
      destination_url: row["destination_url"],
      status_code:     (row["status_code"] || 301).to_i,
      active:          boolean(row["active"], default: true),
      notes:           row["notes"]
    )

    if redirect.save
      existed ? @updated += 1 : @created += 1
    else
      @errors << {row: line, errors: redirect.errors.full_messages}
    end
  end

  def boolean(value, default:)
    case value.to_s.downcase.strip
    when "true", "t", "yes", "y", "1" then true
    when "false", "f", "no", "n", "0" then false
    else default
    end
  end
end
