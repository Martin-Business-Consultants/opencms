# frozen_string_literal: true

module Reports
  module Definitions
    # Google Trends for the tracked keywords: when demand peaks, where in the
    # country it is strongest, and which related queries are rising.
    #
    # Trends is relative, not absolute — 100 is the busiest point in the
    # window — so it complements Keyword demand rather than repeating it:
    # that says how much, this says when and where. The regional map is the
    # local business's chart: the towns where people search for the trade.
    class SearchTrends < Definition
      PATH = "keywords_data/google_trends/explore/live"
      # The live endpoint returns the graph only — `item_types` is a
      # task_post field, and the live API says so with a 40501. The regional
      # map and the related queries are fetched as tasks, one item type each,
      # and waited for. They're the local half of the report, so worth it.
      TASK_PATH = "keywords_data/google_trends/explore"
      # Google Trends' own ceiling.
      MAX_KEYWORDS = 5

      def self.title = "Search trends"

      def self.description
        "Google Trends for the tracked keywords over the last year — the seasonal " \
        "shape, the regions where interest is strongest, and the queries rising alongside."
      end

      def self.group = "Search"
      def self.requires = [:tracked_keywords]
      def self.estimated_cost = 0.01
      def self.cadence = "monthly"
      def self.location_granularity = :country
      def self.locations_api = "dataforseo_labs"

      def self.trend_metrics
        [
          {key: "interest_now", label: "Interest now (0–100)", good: "up"},
          {key: "interest_avg", label: "Average interest", good: nil},
          {key: "rising", label: "Rising queries", good: nil},
          {key: "regions", label: "Regions with interest", good: nil}
        ]
      end

      def self.trend_point(data)
        {
          "interest_now" => data["interest_now"]&.to_f,
          "interest_avg" => data["interest_avg"]&.to_f,
          "rising" => Array(data["rising_queries"]).length,
          "regions" => Array(data["regions"]).length
        }
      end

      def call
        keywords = profile.tracked_keywords.first(MAX_KEYWORDS)
        base = locale_params.merge(keywords: keywords, type: "web", time_range: "past_12_months")

        response = fetch(PATH, base)
        items = Array(response.first&.dig("items"))
        graph = series(items.find { |i| i["type"] == "google_trends_graph" }, keywords)

        regions = regions_for(task_item(base, "google_trends_map"), keywords)
        queries = task_item(base, "google_trends_queries_list")&.dig("data") || {}

        recent = graph.last(4).map { |p| p[:total] }
        all = graph.map { |p| p[:total] }

        locale_data.merge(
          keywords: keywords,
          graph: graph,
          regions: regions,
          top_queries: queries_for(queries["top"]),
          rising_queries: queries_for(queries["rising"]),
          interest_now: recent.any? ? round(recent.sum / recent.length.to_f, 1) : nil,
          interest_avg: all.any? ? round(all.sum / all.length.to_f, 1) : nil,
          peak: graph.max_by { |p| p[:total] }&.dig(:date)
        )
      end

      private

      # One item type via task_post → task_get. Non-fatal: the graph has
      # already been paid for and answers the headline; a missing map is a
      # gap on the page, not a failed report.
      def task_item(base, item_type)
        response = await_task(TASK_PATH, base.merge(item_types: [item_type]), timeout: 120, interval: 3)
        Array(response.first&.dig("items")).find { |i| i["type"] == item_type }
      rescue DataForSeo::Error => e
        warnings << "#{item_type.tr("_", " ")} unavailable: #{e.message.truncate(140)}"
        nil
      end

      # One row per week: the date, each keyword's value by slot, and their
      # sum for the headline.
      def series(item, keywords)
        Array(item&.dig("data")).map do |point|
          values = Array(point["values"]).map(&:to_i)
          row = {date: point["date_from"].to_s, total: values.sum}
          keywords.each_with_index { |_, i| row[:"k#{i}"] = values[i].to_i }
          row
        end
      end

      def regions_for(item, keywords)
        Array(item&.dig("data")).map do |region|
          values = Array(region["values"]).map(&:to_i)
          {name: region["geo_name"].to_s, total: values.sum, top_keyword: keywords[region["max_value_index"].to_i]}
        end.reject { |r| r[:total].zero? }.sort_by { |r| -r[:total] }.first(20)
      end

      def queries_for(list)
        Array(list).map { |q| {query: q["query"].to_s, value: q["value"].to_s} }.first(15)
      end
    end
  end
end
