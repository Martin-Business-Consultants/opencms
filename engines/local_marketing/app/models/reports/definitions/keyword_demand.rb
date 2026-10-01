# frozen_string_literal: true

module Reports
  module Definitions
    # What the tracked keywords are worth, from Google's own numbers.
    #
    # Google Ads search volume is the reference figure everyone else's
    # estimate is calibrated against, and it comes with twelve months of
    # monthly history — which for a local trade is the seasonality chart:
    # storage demand peaks when the students leave, removals peak in summer.
    # One call, one charge, up to a thousand keywords.
    class KeywordDemand < Definition
      PATH = "keywords_data/google_ads/search_volume/live"
      MAX_KEYWORDS = 200

      def self.title = "Keyword demand"

      def self.description
        "Google Ads search volume, CPC and competition for the tracked keywords, " \
        "with twelve months of history — the seasonality of the trade."
      end

      def self.group = "Search"
      def self.requires = [:tracked_keywords]
      def self.estimated_cost = 0.05
      def self.cadence = "monthly"
      # Google Ads has its own location list; the country code is the one
      # value every list agrees on.
      def self.location_granularity = :country
      def self.locations_api = "dataforseo_labs"

      def self.trend_metrics
        [
          {key: "total_volume", label: "Monthly searches", good: "up"},
          {key: "avg_cpc", label: "Average CPC ($)", good: nil},
          {key: "with_volume", label: "Keywords with demand", good: "up"},
          {key: "yoy_pct", label: "Year on year (%)", good: "up"}
        ]
      end

      def self.trend_point(data)
        {
          "total_volume" => data["total_volume"].to_i,
          "avg_cpc" => data["avg_cpc"]&.to_f,
          "with_volume" => Array(data["keywords"]).count { |k| k["search_volume"].to_i.positive? },
          "yoy_pct" => data["yoy_pct"]&.to_f
        }
      end

      def call
        keywords = profile.tracked_keywords.first(MAX_KEYWORDS)
        response = fetch(PATH, locale_params.merge(keywords: keywords, search_partners: false))
        rows = response.result.map { |item| row_for(item) }.reject { |row| row[:keyword].blank? }

        months = seasonality(rows)
        with_cpc = rows.select { |row| row[:cpc].to_f.positive? }

        locale_data.merge(
          keywords: rows.sort_by { |row| -row[:search_volume].to_i },
          total_volume: rows.sum { |row| row[:search_volume].to_i },
          avg_cpc: with_cpc.any? ? round(with_cpc.sum { |row| row[:cpc].to_f } / with_cpc.length) : nil,
          months: months,
          peak_month: months.max_by { |m| m[:volume] }&.dig(:label),
          yoy_pct: yoy(months),
          no_demand: rows.select { |row| row[:search_volume].to_i.zero? }.map { |row| row[:keyword] }
        )
      end

      private

      def row_for(item)
        monthly = Array(item["monthly_searches"]).map do |m|
          {year: m["year"].to_i, month: m["month"].to_i, volume: m["search_volume"].to_i}
        end.sort_by { |m| [m[:year], m[:month]] }

        {
          keyword: item["keyword"].to_s,
          search_volume: item["search_volume"].to_i,
          competition: item["competition"].to_s.downcase.presence,
          competition_index: item["competition_index"]&.to_i,
          cpc: round(item["cpc"]),
          low_bid: round(item["low_top_of_page_bid"]),
          high_bid: round(item["high_top_of_page_bid"]),
          months: monthly
        }
      end

      # Every keyword's monthly volume summed into one series, so the chart
      # shows when the trade is busy rather than when one keyword is.
      def seasonality(rows)
        rows.flat_map { |row| row[:months] }
            .group_by { |m| [m[:year], m[:month]] }
            .map do |(year, month), entries|
              {year: year, month: month, label: format("%04d-%02d", year, month), volume: entries.sum { |m| m[:volume] }}
            end
            .sort_by { |m| [m[:year], m[:month]] }
      end

      def yoy(months)
        return nil if months.length < 13

        latest = months.last[:volume]
        prior = months[-13][:volume]
        return nil if prior.zero?

        round(((latest - prior) / prior.to_f) * 100, 1)
      end
    end
  end
end
