# frozen_string_literal: true

module Reports
  module Definitions
    # Two years of organic history, from DataForSEO's index rather than our
    # snapshots — so the trend exists on day one instead of after ten weeks.
    #
    # Monthly: how many keywords the domain ranked for, how many in the top
    # 3 and top 10, and what the traffic would have cost to buy. The question
    # it answers is "were we growing before we started paying attention",
    # which is the one a new client actually wants answered.
    class VisibilityHistory < Definition
      PATH = "dataforseo_labs/google/historical_rank_overview/live"
      MONTHS_BACK = 24

      def self.title = "Visibility history"

      def self.description
        "Two years of monthly organic history for the domain — keywords ranked, " \
        "top-3 and top-10 counts, and traffic value — from DataForSEO's index."
      end

      def self.group = "Search"
      def self.requires = [:domain]
      def self.estimated_cost = 0.02
      def self.cadence = "monthly"
      def self.location_granularity = :country
      def self.locations_api = "dataforseo_labs"

      def self.trend_metrics
        [
          {key: "ranked", label: "Keywords ranked", good: "up"},
          {key: "top_3", label: "In the top 3", good: "up"},
          {key: "top_10", label: "In the top 10", good: "up"},
          {key: "etv", label: "Traffic value ($)", good: "up"}
        ]
      end

      def self.trend_point(data)
        latest = Array(data["months"]).last || {}
        {
          "ranked" => latest["ranked"].to_i,
          "top_3" => latest["top_3"].to_i,
          "top_10" => latest["top_10"].to_i,
          "etv" => latest["etv"]&.to_f
        }
      end

      def call
        response = fetch(PATH, locale_params.merge(
          target: profile.domain, date_from: MONTHS_BACK.months.ago.to_date.iso8601
        ))
        result = response.first || {}
        months = Array(result["items"]).map { |item| month_for(item) }.sort_by { |m| [m[:year], m[:month]] }

        locale_data.merge(
          domain: profile.domain,
          months: months,
          latest: months.last,
          change_12m: change(months, 12),
          change_3m: change(months, 3),
          best_month: months.max_by { |m| m[:ranked] }&.dig(:label)
        )
      end

      private

      def month_for(item)
        o = item.dig("metrics", "organic") || {}
        top_3 = o["pos_1"].to_i + o["pos_2_3"].to_i
        {
          year: item["year"].to_i,
          month: item["month"].to_i,
          label: format("%04d-%02d", item["year"].to_i, item["month"].to_i),
          ranked: o["count"].to_i,
          top_3: top_3,
          top_10: top_3 + o["pos_4_10"].to_i,
          page_2: o["pos_11_20"].to_i,
          etv: round(o["etv"]),
          new: o["is_new"].to_i,
          lost: o["is_lost"].to_i,
          up: o["is_up"].to_i,
          down: o["is_down"].to_i
        }
      end

      # Percent change in keywords ranked and traffic value over `n` months.
      def change(months, n)
        return nil if months.length <= n

        now = months.last
        then_ = months[-(n + 1)]
        {
          ranked_pct: pct(now[:ranked], then_[:ranked]),
          etv_pct: pct(now[:etv].to_f, then_[:etv].to_f),
          top_10_pct: pct(now[:top_10], then_[:top_10])
        }
      end

      def pct(now, before)
        return nil if before.to_f.zero?

        round(((now - before) / before.to_f) * 100, 1)
      end
    end
  end
end
