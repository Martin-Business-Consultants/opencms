# frozen_string_literal: true

require "rails_helper"

# Every endpoint is CRUD on a resource; a verb that isn't becomes a resource of
# its own (`resource :publication` rather than `post :publish`), as in Fizzy
# (STYLE.md). An old API URL a client depends on keeps working by routing it
# to that resource's controller (`post "pages/bulk_destroy", to: …`).
RSpec.describe "Architecture: CRUD-only routes" do
  PATTERN = /\b(member|collection)\s*(do\b|\{)/

  it "has no member or collection routes" do
    files = Dir.glob(["config/routes.rb", "config/routes/**/*.rb", "engines/*/config/**/*.rb", "engines/*/lib/**/*.rb"],
      base: Rails.root.to_s)
    offenders = files.select { |file| Rails.root.join(file).read.match?(PATTERN) }

    expect(offenders).to be_empty,
      "Custom actions in #{offenders.join(", ")}. Make the verb a resource of its own (STYLE.md)."
  end
end
