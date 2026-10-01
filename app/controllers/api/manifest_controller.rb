# frozen_string_literal: true

# Introspection endpoint for agents (and humans): the shape of this CMS
# (Manifest).
class Api::ManifestController < Api::BaseController
  agent_summary(:show) do |payload|
    counts = payload["counts"] or next nil
    parts = counts.select { |_, n| n.to_i.positive? }
      .map { |thing, n| "#{n} #{thing.humanize(capitalize: false).singularize.pluralize(n)}" }
    brand = payload["brand"].presence ? "brand brief set" : "no brand brief"
    "#{payload["tenant"]}: #{parts.presence&.join(", ") || "empty"} · #{brand}."
  end
  agent_breadcrumbs(:show) do |payload|
    first = payload.dig("collections", 0, "slug")
    [crumb("The pages", "cms pages"),
     first ? crumb("Entries in #{first}", "cms entries #{first}") : nil,
     crumb("The brand brief on its own", "cms brand")].compact
  end

  def show
    @manifest = Manifest.new
  end
end
