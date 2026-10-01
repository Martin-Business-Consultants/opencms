# frozen_string_literal: true

module Reports
  module Definitions
    # How much of the demand for each tracked keyword is now happening inside
    # an AI assistant rather than a search box.
    #
    # The interesting number is not the absolute volume — it's the trend. A
    # keyword whose AI volume is climbing month over month is one where the
    # traditional ranking is quietly becoming worth less, and that is a
    # decision a local business can act on (get the listing and the citations
    # right) long before it shows up as lost traffic.
    #
    # `ai_monthly_searches` is what makes that visible, so the report keeps
    # the series and computes the direction rather than storing a single
    # point that means nothing on its own.
    class AiKeywordDemand < Definition
      PATH = "ai_optimization/ai_keyword_data/keywords_search_volume/live"

      # The endpoint takes up to 1000, but a local business tracking 1000
      # keywords is a configuration mistake, not a use case. Capped low
      # enough that a paste-gone-wrong can't run up a bill.
      MAX_KEYWORDS = 200

      # Compare the last three months against the three before them. One
      # month against one month is noise; a year is too slow to act on.
      WINDOW = 3

      def self.title = "AI keyword demand"

      def self.description
        "AI search volume for the tracked keywords, with the trend over the " \
        "last six months — which queries are moving into AI assistants."
      end

      def self.group = "AI visibility"
      def self.requires = [:tracked_keywords]
      def self.estimated_cost = 0.01
      def self.cadence = "monthly"

      # Its own list — 94 countries, not the same 92 LLM Mentions publishes.
      def self.location_granularity = :country
      def self.locations_api = "ai_keyword_data"

      def self.trend_metrics
        [
          {key: "total_volume", label: "Total AI volume", good: "up"},
          {key: "rising", label: "Rising keywords", good: "up"},
          {key: "falling", label: "Falling keywords", good: "down"},
          {key: "absent", label: "No AI demand", good: "down"}
        ]
      end

      def self.trend_point(data)
        {
          "total_volume" => data["total_volume"].to_i,
          "rising" => Array(data["rising"]).length,
          "falling" => Array(data["falling"]).length,
          "absent" => Array(data["absent"]).length
        }
      end

      def call
        keywords = profile.tracked_keywords.first(MAX_KEYWORDS)
        response = fetch(PATH, locale_params.merge(keywords: keywords))
        rows = Array(response.first&.dig("items") || response.result).map { |item| row_for(item) }

        locale_data.merge(
          keywords: rows.sort_by { |row| -row[:ai_search_volume].to_i },
          total_volume: rows.sum { |row| row[:ai_search_volume].to_i },
          rising: rows.select { |row| row[:change_pct].to_f > 10 }.map { |row| row[:keyword] },
          falling: rows.select { |row| row[:change_pct].to_f < -10 }.map { |row| row[:keyword] },
          # A keyword with no AI volume at all is a real finding, not a gap
          # in the data — it means the query is still a search-box query.
          absent: rows.select { |row| row[:ai_search_volume].to_i.zero? }.map { |row| row[:keyword] }
        )
      end

      private

      def row_for(item)
        series = monthly_series(item["ai_monthly_searches"])

        {
          keyword: item["keyword"].to_s,
          ai_search_volume: item["ai_search_volume"].to_i,
          months: series,
          change_pct: change_pct(series)
        }
      end

      # Oldest first, which is the order a sparkline wants and the opposite
      # of the order DataForSEO sends.
      def monthly_series(rows)
        Array(rows)
          .map do |row|
            {
              year: row["year"].to_i,
              month: row["month"].to_i,
              volume: row["ai_search_volume"].to_i
            }
          end
          .sort_by { |row| [row[:year], row[:month]] }
      end

      # nil rather than 0 when there isn't enough history: "flat" and "we
      # don't know yet" must not render as the same thing.
      def change_pct(series)
        return nil if series.length < WINDOW * 2

        recent = series.last(WINDOW).sum { |row| row[:volume] }
        prior  = series[-(WINDOW * 2)...-WINDOW].sum { |row| row[:volume] }
        return nil if prior.zero?

        round(((recent - prior) / prior.to_f) * 100, 1)
      end
    end
  end
end
