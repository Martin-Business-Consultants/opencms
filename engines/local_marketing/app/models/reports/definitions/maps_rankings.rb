# frozen_string_literal: true

module Reports
  module Definitions
    # Where the business ranks in Google Maps itself, per tracked keyword.
    #
    # Local rankings reads the three-pack embedded in a web search. This is
    # the Maps surface proper — what someone sees when they open the Maps
    # app and type "storage near me" — where twenty results show, ratings
    # decide the order and a claimed, complete listing is the whole game.
    # It also tells us the business's own coordinates and category, which
    # Local competitors needs.
    class MapsRankings < Definition
      PATH = "serp/google/maps/live/advanced"
      MAX_KEYWORDS = 25
      DEPTH = 20
      DEVICE = "mobile"

      def self.title = "Maps rankings"

      def self.description
        "Position in Google Maps for each tracked keyword, from the business's own " \
        "location — and who ranks above it, with their ratings."
      end

      def self.group = "Local"
      def self.requires = [:tracked_keywords, :business_name]
      def self.estimated_cost = 0.05
      def self.cadence = "weekly"
      def self.location_granularity = :city
      def self.locations_api = "serp_google"

      def self.trend_metrics
        [
          {key: "in_top_3", label: "In the top 3", good: "up"},
          {key: "in_top_10", label: "In the top 10", good: "up"},
          {key: "not_found", label: "Not in the top 20", good: "down"},
          {key: "avg_position", label: "Average position", good: "down"}
        ]
      end

      def self.trend_point(data)
        found = Array(data["keywords"]).filter_map { |k| k["position"] }
        {
          "in_top_3" => data["in_top_3"].to_i,
          "in_top_10" => data["in_top_10"].to_i,
          "not_found" => Array(data["not_found"]).length,
          "avg_position" => found.any? ? (found.sum / found.length.to_f).round(1) : nil
        }
      end

      def call
        keywords = profile.tracked_keywords.first(MAX_KEYWORDS)
        responses = fetch_many(PATH, keywords.map { |k| locale_params.merge(keyword: k, depth: DEPTH, device: DEVICE) })
        rows = keywords.zip(responses).map { |k, r| row_for(k, r) }
        ranked = rows.reject { |row| row[:error] }
        ours = ranked.filter_map { |row| row[:listing] }.first

        locale_data.merge(
          keywords: rows,
          in_top_3: ranked.count { |row| row[:position].to_i.between?(1, 3) },
          in_top_10: ranked.count { |row| row[:position].to_i.between?(1, 10) },
          not_found: ranked.select { |row| row[:position].nil? }.map { |row| row[:keyword] },
          listing: ours,
          rivals: rival_counts(ranked)
        )
      end

      private

      def row_for(keyword, response)
        # Same shape as a good row — see LocalRankings#row_for.
        if response.nil? || response.empty?
          return {keyword: keyword, error: "No result returned", position: nil, rating: nil, reviews: nil,
                  results: 0, above: [], listing: nil}
        end

        items = Array(response.first["items"]).select { |i| i["type"] == "maps_search" }
        ours = items.find { |i| mine?(i) }
        above = ours ? items.take(items.index(ours)) : items.first(3)

        {
          keyword: keyword,
          position: ours&.dig("rank_group"),
          rating: ours&.dig("rating", "value"),
          reviews: ours&.dig("rating", "votes_count"),
          results: items.length,
          above: above.first(5).map { |i| listing_of(i) },
          listing: ours && listing_of(ours).merge(latitude: ours["latitude"], longitude: ours["longitude"],
                                                  place_id: ours["place_id"].to_s, cid: ours["cid"].to_s,
                                                  category: ours["category"].to_s, is_claimed: ours["is_claimed"])
        }
      end

      def listing_of(item)
        {title: item["title"].to_s, domain: item["domain"].to_s, rating: item.dig("rating", "value"),
         reviews: item.dig("rating", "votes_count").to_i, position: item["rank_group"]}
      end

      def mine?(item)
        return true if profile.cid.present? && item["cid"].to_s == profile.cid
        return true if profile.place_id.present? && item["place_id"].to_s == profile.place_id
        return true if profile.domain.present? && same_domain?(item["domain"])

        profile.brand_terms.any? { |t| item["title"].to_s.casecmp?(t) }
      end

      def same_domain?(value)
        host = value.to_s.downcase.sub(/\Awww\./, "")
        host == profile.domain.downcase || host.end_with?(".#{profile.domain.downcase}")
      end

      def rival_counts(rows)
        rows.flat_map { |row| Array(row[:above]) }
            .reject { |l| same_domain?(l[:domain]) }
            .group_by { |l| l[:title] }
            .map { |title, ls| {title: title, appearances: ls.length, rating: ls.first[:rating], reviews: ls.first[:reviews], domain: ls.first[:domain]} }
            .sort_by { |r| -r[:appearances] }.first(10)
      end
    end
  end
end
