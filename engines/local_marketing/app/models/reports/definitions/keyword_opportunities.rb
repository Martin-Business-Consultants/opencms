# frozen_string_literal: true

module Reports
  module Definitions
    # Demand around the tracked keywords that the site may not be capturing.
    #
    # Keyword ideas are the queries Google groups with ours — the long tail
    # a local business never thinks to write for ("storage units cardiff"
    # begets "student storage cardiff summer"). Each comes with volume,
    # difficulty and intent. Cross-referenced against the latest Ranked
    # keywords snapshot, so the ones we already rank for are marked and the
    # "easy wins" — real volume, low difficulty, not ranking — float up.
    class KeywordOpportunities < Definition
      PATH = "dataforseo_labs/google/keyword_ideas/live"
      MAX_SEEDS = 20
      LIMIT = 300

      EASY_DIFFICULTY = 30
      EASY_VOLUME = 50

      def self.title = "Keyword opportunities"

      def self.description
        "Queries Google groups with the tracked keywords — volume, difficulty and intent — " \
        "with the ones we already rank for marked, so the easy wins stand out."
      end

      def self.group = "Search"
      def self.requires = [:tracked_keywords]
      def self.estimated_cost = 0.03
      def self.cadence = "monthly"
      def self.location_granularity = :country
      def self.locations_api = "dataforseo_labs"

      def self.trend_metrics
        [
          {key: "total_count", label: "Ideas", good: nil},
          {key: "total_volume", label: "Monthly searches", good: nil},
          {key: "easy_wins", label: "Easy wins", good: "up"},
          {key: "already_ranking", label: "Already ranking", good: "up"}
        ]
      end

      def self.trend_point(data)
        {
          "total_count" => data["total_count"].to_i,
          "total_volume" => data["total_volume"].to_i,
          "easy_wins" => Array(data["easy_wins"]).length,
          "already_ranking" => Array(data["ideas"]).count { |i| i["ranking_position"] }
        }
      end

      def call
        seeds = profile.tracked_keywords.first(MAX_SEEDS)
        response = fetch(PATH, locale_params.merge(
          keywords: seeds, limit: LIMIT, include_serp_info: false,
          order_by: ["keyword_info.search_volume,desc"],
          filters: [["keyword_info.search_volume", ">", 10]]
        ))
        result = response.first || {}
        ranking = ranking_positions
        rows = Array(result["items"]).map { |item| row_for(item, ranking) }.reject { |row| row[:keyword].blank? }

        locale_data.merge(
          seeds: seeds,
          total_count: result["total_count"].to_i,
          returned: rows.length,
          total_volume: rows.sum { |row| row[:search_volume].to_i },
          ideas: rows,
          easy_wins: rows.select { |row| easy?(row) }.first(50),
          by_intent: rows.group_by { |row| row[:intent] || "unknown" }.transform_values(&:length),
          cross_referenced: ranking.any?
        )
      end

      private

      def row_for(item, ranking)
        info = item["keyword_info"] || {}
        keyword = item["keyword"].to_s

        {
          keyword: keyword,
          search_volume: info["search_volume"].to_i,
          cpc: round(info["cpc"]),
          competition: info["competition_level"].to_s.downcase.presence,
          difficulty: item.dig("keyword_properties", "keyword_difficulty")&.to_i,
          intent: item.dig("search_intent_info", "main_intent").to_s.presence,
          ranking_position: ranking[keyword.downcase]
        }
      end

      def easy?(row)
        row[:ranking_position].nil? &&
          row[:search_volume].to_i >= EASY_VOLUME &&
          (row[:difficulty].nil? || row[:difficulty] <= EASY_DIFFICULTY)
      end

      # keyword → best position, from the latest complete Ranked keywords
      # run. Best-effort: with none, nothing is marked and the report says so.
      def ranking_positions
        latest = Report.latest_by_kind["ranked_keywords"]
        return {} unless latest

        Array(latest.data["keywords"]).each_with_object({}) do |row, acc|
          key = row["keyword"].to_s.downcase
          pos = row["position"].to_i
          acc[key] = pos if pos.positive? && (acc[key].nil? || pos < acc[key])
        end
      end
    end
  end
end
