# frozen_string_literal: true

module Reports
  module Definitions
    # The most recent Google reviews, read for what an owner needs to act on.
    #
    # The only task-based report in the catalog: Google reviews can't be
    # fetched live, so this posts a task and waits (see Definition#await_task).
    # What it looks for is not the average — Business profile has that — but
    # the shape underneath it: how many recent reviews are 1–2 stars, how
    # many went unanswered, and whether the last ten read better or worse
    # than the whole. Replying to reviews is the cheapest reputation work
    # there is, and the unanswered count is the to-do list.
    class GoogleReviews < Definition
      PATH = "business_data/google/reviews"
      DEPTH = 50
      RECENT = 10
      LOW = 2
      EXCERPT = 280

      def self.title = "Google reviews"

      def self.description
        "The #{DEPTH} most recent Google reviews — rating shape, unanswered reviews, " \
        "recent low scores, and what people actually wrote."
      end

      def self.group = "Reputation"
      def self.requires = [:business_name]
      def self.estimated_cost = 0.01
      def self.cadence = "weekly"
      def self.location_granularity = :city
      def self.locations_api = "business_data_google"

      def self.trend_metrics
        [
          {key: "rating", label: "Rating", good: "up"},
          {key: "reviews_count", label: "Reviews", good: "up"},
          {key: "unanswered", label: "Unanswered", good: "down"},
          {key: "recent_low", label: "Recent 1–2★", good: "down"}
        ]
      end

      def self.trend_point(data)
        {
          "rating" => data["rating"]&.to_f,
          "reviews_count" => data["reviews_count"].to_i,
          "unanswered" => data["unanswered"].to_i,
          "recent_low" => data["recent_low"].to_i
        }
      end

      def call
        response = await_task(PATH, task)
        result = response.first || {}
        reviews = Array(result["items"]).select { |i| i["type"] == "google_reviews_search" }.map { |i| review_for(i) }
        recent = reviews.first(RECENT)

        locale_data.merge(
          title: result["title"].to_s,
          rating: result.dig("rating", "value")&.to_f,
          reviews_count: result["reviews_count"].to_i,
          fetched: reviews.length,
          distribution: (1..5).to_h { |star| [star.to_s, reviews.count { |r| r[:rating] == star }] },
          unanswered: reviews.count { |r| !r[:answered] },
          answered_pct: reviews.any? ? ((reviews.count { |r| r[:answered] } / reviews.length.to_f) * 100).round : nil,
          recent_rating: recent.any? ? round(recent.sum { |r| r[:rating].to_f } / recent.length, 2) : nil,
          recent_low: recent.count { |r| r[:rating].to_i <= LOW },
          low_unanswered: reviews.select { |r| r[:rating].to_i <= LOW && !r[:answered] },
          reviews: reviews
        )
      end

      private

      def task
        base = locale_params.merge(depth: DEPTH, sort_by: "newest")
        return base.merge(place_id: profile.place_id) if profile.place_id.present?
        return base.merge(cid: profile.cid) if profile.cid.present?

        base.merge(keyword: profile.business_name)
      end

      def review_for(item)
        {
          rating: item.dig("rating", "value").to_i,
          text: item["review_text"].to_s.strip.truncate(EXCERPT),
          time_ago: item["time_ago"].to_s,
          timestamp: item["timestamp"].to_s,
          author: item["profile_name"].to_s,
          local_guide: item["local_guide"] == true,
          answered: item["owner_answer"].to_s.strip.present?,
          answer: item["owner_answer"].to_s.strip.truncate(EXCERPT).presence,
          url: item["review_url"].to_s
        }
      end
    end
  end
end
