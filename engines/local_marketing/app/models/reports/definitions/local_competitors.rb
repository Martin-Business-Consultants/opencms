# frozen_string_literal: true

module Reports
  module Definitions
    # Every business in the same category within reach, with ratings and
    # review counts — the local field as Google Maps holds it.
    #
    # Two calls. The first finds the business itself on Maps (its
    # coordinates and its category — the Business Listings index has no
    # notion of a city, only a radius around a point). The second lists
    # everything in that category around it. The result is the league table
    # a local owner actually wants: where do we sit on reviews and rating
    # against the people a customer would see next to us.
    class LocalCompetitors < Definition
      FIND_PATH = "serp/google/maps/live/advanced"
      PATH = "business_data/business_listings/search/live"
      RADIUS_KM = 15
      LIMIT = 60

      def self.title = "Local competitors"

      def self.description
        "Every listing in the same category within #{RADIUS_KM} km, ranked by reviews and " \
        "rating — where the business sits in its own local field."
      end

      def self.group = "Local"
      def self.requires = [:business_name]
      def self.estimated_cost = 0.02
      def self.cadence = "monthly"
      def self.location_granularity = :city
      def self.locations_api = "serp_google"

      def self.trend_metrics
        [
          {key: "competitors", label: "Competitors nearby", good: nil},
          {key: "review_rank", label: "Our rank by reviews", good: "down"},
          {key: "rating_rank", label: "Our rank by rating", good: "down"},
          {key: "avg_rating", label: "Field average rating", good: nil}
        ]
      end

      def self.trend_point(data)
        {
          "competitors" => Array(data["competitors"]).length,
          "review_rank" => data.dig("ours", "review_rank"),
          "rating_rank" => data.dig("ours", "rating_rank"),
          "avg_rating" => data["avg_rating"]&.to_f
        }
      end

      def call
        ours = find_ours
        response = fetch(PATH, {
          location_coordinate: "#{ours[:latitude]},#{ours[:longitude]},#{RADIUS_KM}",
          filters: [["category", "=", ours[:category]]],
          order_by: ["rating.votes_count,desc"],
          limit: LIMIT
        })
        rows = Array(response.first&.dig("items")).map { |i| row_for(i, ours) }
        field = rows.reject { |r| r[:mine] }
        rated = field.select { |r| r[:rating] }

        by_reviews = rows.sort_by { |r| -r[:reviews].to_i }
        by_rating = rows.select { |r| r[:rating] }.sort_by { |r| [-r[:rating].to_f, -r[:reviews].to_i] }
        me = rows.find { |r| r[:mine] }

        locale_data.merge(
          category: ours[:category],
          radius_km: RADIUS_KM,
          centre: {latitude: ours[:latitude], longitude: ours[:longitude]},
          ours: me && me.merge(
            review_rank: by_reviews.index(me) + 1,
            rating_rank: by_rating.index(me)&.+(1)
          ),
          competitors: field.first(LIMIT),
          avg_rating: rated.any? ? round(rated.sum { |r| r[:rating].to_f } / rated.length, 2) : nil,
          median_reviews: median(field.map { |r| r[:reviews].to_i }),
          claimed_pct: field.any? ? ((field.count { |r| r[:is_claimed] } / field.length.to_f) * 100).round : nil
        )
      end

      private

      # Our own listing on Maps: coordinates and category.
      def find_ours
        response = fetch(FIND_PATH, locale_params.merge(keyword: profile.business_name, depth: 10))
        items = Array(response.first&.dig("items")).select { |i| i["type"] == "maps_search" }
        item = items.find { |i| mine?(i) } || items.first
        if item.nil? || item["latitude"].nil?
          raise DataForSeo::Error, "Couldn't find #{profile.business_name.inspect} on Google Maps near #{locale.location_name}. " \
                                   "Check the business name — or set the Google place ID — under Settings → Reporting."
        end

        {latitude: item["latitude"], longitude: item["longitude"], category: item["category"].to_s,
         cid: item["cid"].to_s, title: item["title"].to_s}
      end

      def row_for(item, ours)
        {
          title: item["title"].to_s,
          domain: item["domain"].to_s,
          address: item["address"].to_s,
          rating: item.dig("rating", "value")&.to_f,
          reviews: item.dig("rating", "votes_count").to_i,
          is_claimed: item["is_claimed"] == true,
          photos: item["total_photos"].to_i,
          distance_km: distance(ours, item),
          mine: item["cid"].to_s == ours[:cid] || mine?(item)
        }
      end

      def mine?(item)
        return true if profile.cid.present? && item["cid"].to_s == profile.cid
        return true if profile.place_id.present? && item["place_id"].to_s == profile.place_id
        return true if profile.domain.present? && item["domain"].to_s.downcase.sub(/\Awww\./, "").end_with?(profile.domain.downcase)

        profile.brand_terms.any? { |t| item["title"].to_s.casecmp?(t) }
      end

      # Haversine, in km to one decimal.
      def distance(ours, item)
        lat1, lon1 = ours[:latitude].to_f, ours[:longitude].to_f
        lat2, lon2 = item["latitude"].to_f, item["longitude"].to_f
        return nil if lat2.zero? && lon2.zero?

        rad = Math::PI / 180
        dlat = (lat2 - lat1) * rad
        dlon = (lon2 - lon1) * rad
        a = (Math.sin(dlat / 2)**2) + (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlon / 2)**2))
        (6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))).round(1)
      end

      def median(values)
        return nil if values.empty?

        sorted = values.sort
        mid = sorted.length / 2
        sorted.length.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
      end
    end
  end
end
