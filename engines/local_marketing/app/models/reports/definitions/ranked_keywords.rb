# frozen_string_literal: true

module Reports
  module Definitions
    # What the site already ranks for, from DataForSEO's own index — no
    # Search Console connection, no property verification, no waiting three
    # days for data. One live call against a domain.
    #
    # For a local business this is usually the first honest answer anyone has
    # given them about their own site, and the two numbers that matter are in
    # `metrics`: how many keywords sit in the top 3 (where local intent
    # actually converts) and how many are on page two, which is the cheapest
    # work available — those are pages that already almost rank.
    #
    # `local_pack` is requested alongside `organic` deliberately. A storage
    # company ranking 8th organically but 2nd in the map pack is doing fine,
    # and a report that only counted organic would tell them the opposite.
    class RankedKeywords < Definition
      PATH = "dataforseo_labs/google/ranked_keywords/live"

      ITEM_TYPES = %w[organic local_pack ai_overview_reference].freeze
      LIMIT = 200

      # Position 4–10 is "on page one but below the fold and below the map
      # pack"; 11–20 is page two. Both are within reach, and they want
      # different work, so they're counted apart.
      STRIKING_DISTANCE = (4..20)

      def self.title = "Ranked keywords"

      def self.description
        "Every keyword this domain already ranks for — organic, map pack and " \
        "AI Overview citations — with the ones sitting just off page one."
      end

      def self.group = "Search"
      def self.requires = [:domain]
      def self.estimated_cost = 0.02
      def self.cadence = "weekly"

      # DataForSEO Labs is country-level only — 90 of them, no cities. The
      # city that makes Local rankings correct comes back from here as
      # `40501 Invalid Field: 'location_name'`.
      def self.location_granularity = :country
      def self.locations_api = "dataforseo_labs"

      def self.trend_metrics
        [
          {key: "total_count", label: "Keywords ranked", good: "up"},
          {key: "top_3", label: "In the top 3", good: "up"},
          {key: "striking_distance", label: "Striking distance", good: "up"},
          {key: "etv", label: "Traffic value ($)", good: "up"}
        ]
      end

      def self.trend_point(data)
        {
          "total_count" => data["total_count"].to_i,
          "top_3" => data["top_3"].to_i,
          "striking_distance" => Array(data["striking_distance"]).length,
          "etv" => data.dig("metrics", "organic", "etv")&.to_f&.round
        }
      end

      def call
        response = fetch(PATH, locale_params.merge(
          target: profile.domain,
          item_types: ITEM_TYPES,
          limit: LIMIT,
          order_by: ["keyword_data.keyword_info.search_volume,desc"]
        ))

        result = response.first || {}
        keywords = Array(result["items"]).map { |item| keyword_row(item) }.compact

        locale_data.merge(
          domain: profile.domain,
          total_count: result["total_count"].to_i,
          returned: keywords.length,
          metrics: summarize(result["metrics"]),
          top_3: keywords.select { |k| k[:position].to_i.between?(1, 3) }.length,
          striking_distance: keywords.select { |k| STRIKING_DISTANCE.cover?(k[:position].to_i) }
                                     .sort_by { |k| -k[:search_volume].to_i }
                                     .first(50),
          keywords: keywords.first(LIMIT)
        )
      end

      private

      def keyword_row(item)
        serp = item["ranked_serp_element"]&.dig("serp_item") || {}
        info = item.dig("keyword_data", "keyword_info") || {}
        keyword = item.dig("keyword_data", "keyword").to_s
        return nil if keyword.blank?

        {
          keyword: keyword,
          position: serp["rank_group"].to_i,
          type: serp["type"].to_s,
          url: serp["url"].to_s,
          search_volume: info["search_volume"].to_i,
          cpc: round(info["cpc"]),
          competition: info["competition_level"].to_s.downcase.presence,
          # Estimated traffic value: what this ranking would cost to buy.
          # The number that makes an SEO report legible to an owner who
          # already knows what a click costs them.
          etv: round(item["ranked_serp_element"]&.dig("etv"))
        }
      end

      # `metrics` arrives keyed by item type, each with pos_1 … pos_91_100
      # buckets. Only the shape of the distribution is worth keeping.
      def summarize(metrics)
        (metrics || {}).transform_values do |m|
          next nil unless m.is_a?(Hash)

          {
            count: m["count"].to_i,
            etv: round(m["etv"]),
            pos_1: m["pos_1"].to_i,
            pos_2_3: m["pos_2_3"].to_i,
            pos_4_10: m["pos_4_10"].to_i,
            pos_11_20: m["pos_11_20"].to_i,
            is_up: m["is_up"].to_i,
            is_down: m["is_down"].to_i,
            is_new: m["is_new"].to_i,
            is_lost: m["is_lost"].to_i
          }
        end.compact
      end
    end
  end
end
