# frozen_string_literal: true

require "rails_helper"

# API responses are built by jbuilder views (app/views/api/…), so a record's
# JSON has one definition that every endpoint shares (STYLE.md). Controllers
# render JSON themselves only for error bodies (`render json: {error: …}`,
# on one line).
RSpec.describe "Architecture: API JSON comes from views" do
  RENDER_JSON = /render\(?\s*json:/
  ERROR_BODY = /json:\s*\{\s*error:/

  it "builds success bodies in jbuilder views" do
    files = Dir.glob(["app/controllers/api/**/*.rb", "engines/*/app/controllers/api/**/*.rb"], base: Rails.root.to_s)
    offenders = files.flat_map do |file|
      Rails.root.join(file).each_line.with_index(1).filter_map do |line, number|
        "#{file}:#{number}" if line.match?(RENDER_JSON) && !line.match?(ERROR_BODY)
      end
    end

    expect(offenders).to be_empty,
      "Hand-built JSON at #{offenders.join(", ")}. Render a jbuilder view instead (app/views/api/…)."
  end
end
