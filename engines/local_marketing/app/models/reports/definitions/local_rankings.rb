# frozen_string_literal: true

module Reports
  module Definitions
    # Where the business actually shows up for its own keywords, in the place
    # it trades — map pack and organic, side by side.
    #
    # This is the only report here that asks Google directly rather than
    # reading an index, and it is the one clients recognise: "am I in the
    # three-pack for 'storage units cardiff'". The map pack is read first
    # because for a local query it sits above the organic results and takes
    # most of the clicks; an organic position with no map pack presence is a
    # different problem (and a different fix) from the reverse.
    #
    # One live SERP call per keyword, batched into one HTTP request. That
    # makes this the most expensive report in the catalog, which is why the
    # keyword cap is low and the cost is shown on the button.
    class LocalRankings < Definition
      PATH = "serp/google/organic/live/advanced"

      MAX_KEYWORDS = 25
      # Deep enough to find a position worth reporting; past 30 nobody is
      # getting clicked and the extra depth costs money.
      DEPTH = 30

      # Local intent is overwhelmingly phone-first, and Google returns
      # different results by device. Asking on desktop would answer a
      # question nobody's customers are asking.
      DEVICE = "mobile"

      def self.title = "Local rankings"

      def self.description
        "Live map-pack and organic positions for the tracked keywords, on " \
        "mobile, from the business's own location."
      end

      def self.group = "Local"
      def self.requires = [:tracked_keywords, :domain]
      def self.estimated_cost = 0.05
      def self.cadence = "weekly"

      # A map-pack position IS a city question — this is the one report where
      # the city granularity is the whole point.
      def self.location_granularity = :city
      def self.locations_api = "serp_google"

      def self.trend_metrics
        [
          {key: "in_map_pack", label: "In the map pack", good: "up"},
          {key: "in_top_3_organic", label: "Top 3 organic", good: "up"},
          {key: "not_ranking", label: "Not ranking", good: "down"},
          {key: "checked", label: "Keywords checked", good: nil}
        ]
      end

      def self.trend_point(data)
        rows = Array(data["keywords"]).reject { |row| row["error"] }
        {
          "in_map_pack" => data["in_map_pack"].to_i,
          "in_top_3_organic" => data["in_top_3_organic"].to_i,
          "not_ranking" => Array(data["not_ranking"]).length,
          "checked" => rows.length
        }
      end

      def call
        keywords = profile.tracked_keywords.first(MAX_KEYWORDS)
        responses = fetch_many(PATH, keywords.map { |keyword| task_for(keyword) })

        rows = keywords.zip(responses).map { |keyword, response| row_for(keyword, response) }
        ranked = rows.reject { |row| row[:error] }

        {
          domain: profile.domain,
          # As resolved, not as typed — the name DataForSEO filed it under.
          location: locale.location_name,
          device: DEVICE,
          keywords: rows,
          in_map_pack: ranked.count { |row| row[:local_pack_position] },
          in_top_3_organic: ranked.count { |row| row[:organic_position].to_i.between?(1, 3) },
          not_ranking: ranked.select { |row| row[:organic_position].nil? && row[:local_pack_position].nil? }
                             .map { |row| row[:keyword] },
          # Who holds the pack when we don't. Counted across every keyword,
          # because the same two or three businesses usually hold all of them
          # and that is the competitive picture in one number.
          map_pack_rivals: rival_counts(ranked)
        }
      end

      private

      def task_for(keyword)
        locale_params.merge(keyword: keyword, device: DEVICE, depth: DEPTH)
      end

      def row_for(keyword, response)
        # Same shape as a good row, so nothing downstream has to know which
        # kind it holds — an error row is a row with nothing in it.
        if response.nil? || response.empty?
          return {keyword: keyword, error: "No result returned", organic_position: nil, organic_url: nil,
                  local_pack_position: nil, rating: nil, reviews: nil, local_pack: [], has_ai_overview: false,
                  total_results: nil}
        end

        items = Array(response.first["items"])
        local_pack = items.select { |item| item["type"] == "local_pack" }
        ours = local_pack.find { |item| mine?(item) }
        organic = items.find { |item| item["type"] == "organic" && domain_matches?(item["domain"]) }

        {
          keyword: keyword,
          organic_position: organic&.dig("rank_group"),
          organic_url: organic&.dig("url"),
          local_pack_position: ours && local_pack.index(ours) + 1,
          rating: ours&.dig("rating", "value"),
          reviews: ours&.dig("rating", "votes_count"),
          # Present regardless of whether we're in it — "who is in the pack"
          # is the useful half when the answer to "are we" is no.
          local_pack: local_pack.first(3).map { |item| {title: item["title"].to_s, domain: item["domain"].to_s} },
          has_ai_overview: items.any? { |item| item["type"] == "ai_overview" },
          total_results: response.first["se_results_count"]
        }
      end

      # Match on the place first when we have one — a business with a
      # separate booking domain is still the same business, and the CID is
      # the only identifier Google considers authoritative.
      def mine?(item)
        return true if profile.cid.present? && item["cid"].to_s == profile.cid

        domain_matches?(item["domain"])
      end

      def domain_matches?(value)
        return false if profile.domain.blank?

        host = value.to_s.downcase.sub(/\Awww\./, "")
        host == profile.domain.downcase || host.end_with?(".#{profile.domain.downcase}")
      end

      def rival_counts(rows)
        rows
          .flat_map { |row| Array(row[:local_pack]) }
          .reject { |entry| domain_matches?(entry[:domain]) }
          .group_by { |entry| entry[:title] }
          .map { |title, entries| {title: title, appearances: entries.length, domain: entries.first[:domain]} }
          .sort_by { |entry| -entry[:appearances] }
          .first(10)
      end
    end
  end
end
