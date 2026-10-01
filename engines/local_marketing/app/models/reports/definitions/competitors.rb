# frozen_string_literal: true

module Reports
  module Definitions
    # Who ranks for the same keywords we do — the competitive set as Google
    # sees it, which is frequently not the one the owner would name.
    #
    # `intersections` is the number of keywords a domain shares with ours;
    # `full_domain_metrics` is its whole footprint. A domain with many
    # intersections and a much larger footprint is the one to study; one with
    # few intersections and a huge footprint is a directory, not a rival.
    class Competitors < Definition
      PATH = "dataforseo_labs/google/competitors_domain/live"
      LIMIT = 30

      def self.title = "Competitors"

      def self.description
        "Domains ranking for the same keywords, by how much they overlap with us " \
        "and how big they are — the competitive set as Google sees it."
      end

      def self.group = "Search"
      def self.requires = [:domain]
      def self.estimated_cost = 0.02
      def self.cadence = "monthly"
      def self.location_granularity = :country
      def self.locations_api = "dataforseo_labs"

      def self.trend_metrics
        [
          {key: "total_count", label: "Competing domains", good: nil},
          {key: "top_overlap", label: "Most shared keywords", good: nil},
          {key: "known", label: "Named competitors found", good: nil},
          {key: "bigger_than_us", label: "Bigger than us", good: "down"}
        ]
      end

      def self.trend_point(data)
        {
          "total_count" => data["total_count"].to_i,
          "top_overlap" => Array(data["competitors"]).map { |c| c["intersections"].to_i }.max,
          "known" => Array(data["competitors"]).count { |c| c["known"] },
          "bigger_than_us" => Array(data["competitors"]).count { |c| c["bigger"] }
        }
      end

      def call
        response = fetch(PATH, locale_params.merge(
          target: profile.domain, limit: LIMIT, exclude_top_domains: true,
          item_types: %w[organic local_pack], order_by: ["intersections,desc"]
        ))
        result = response.first || {}
        rows = Array(result["items"]).map { |item| row_for(item) }.reject { |row| row[:domain].blank? }

        ours = rows.find { |row| same_domain?(row[:domain]) }
        our_count = ours&.dig(:keywords).to_i
        rows.each { |row| row[:bigger] = our_count.positive? && row[:keywords].to_i > our_count && !same_domain?(row[:domain]) }

        locale_data.merge(
          domain: profile.domain,
          total_count: result["total_count"].to_i,
          our_keywords: our_count,
          our_etv: ours&.dig(:etv),
          competitors: rows.reject { |row| same_domain?(row[:domain]) },
          known_competitors: profile.competitors,
          missing_known: profile.competitors.reject { |c| rows.any? { |row| row[:domain].end_with?(c.downcase.sub(/\Awww\./, "")) } }
        )
      end

      private

      def row_for(item)
        full = item.dig("full_domain_metrics", "organic") || {}
        shared = item.dig("metrics", "organic") || {}
        domain = item["domain"].to_s.downcase

        {
          domain: domain,
          avg_position: round(item["avg_position"], 1),
          intersections: item["intersections"].to_i,
          keywords: full["count"].to_i,
          etv: round(full["etv"]),
          top_3: full["pos_1"].to_i + full["pos_2_3"].to_i,
          top_10: full["pos_1"].to_i + full["pos_2_3"].to_i + full["pos_4_10"].to_i,
          shared_etv: round(shared["etv"]),
          shared_top_10: shared["pos_1"].to_i + shared["pos_2_3"].to_i + shared["pos_4_10"].to_i,
          known: profile.competitors.any? { |c| domain.end_with?(c.downcase.sub(/\Awww\./, "")) }
        }
      end

      def same_domain?(domain)
        bare = profile.domain.downcase
        domain == bare || domain.end_with?(".#{bare}")
      end
    end
  end
end
