# frozen_string_literal: true

module Reports
  module Definitions
    # The Google Business Profile as the public sees it, plus the things that
    # are wrong with it.
    #
    # For a local business the listing outranks the website for most queries
    # that matter, and it is usually the least maintained asset they own —
    # hours that went stale at Christmas, a category that was guessed at
    # setup, no description, three photos. None of that needs a developer to
    # fix, which is exactly why it is worth surfacing: this is the report
    # where the recommended actions are all things the owner can do in an
    # afternoon.
    #
    # `place_topics` is kept because it is the one field here that is not
    # about the listing at all — it is the vocabulary customers use in
    # reviews, which is the closest thing to free keyword research a local
    # business has.
    class BusinessProfile < Definition
      PATH = "business_data/google/my_business_info/live"

      # Google truncates hard in the pack. Anything past this isn't read.
      DESCRIPTION_MIN = 100

      def self.title = "Business profile"

      def self.description
        "The Google Business Profile — rating, reviews, categories, hours and " \
        "photos — with the gaps that cost visibility in the map pack."
      end

      def self.group = "Local"
      def self.requires = [:business_name]
      def self.estimated_cost = 0.02
      def self.cadence = "monthly"

      # A listing is at an address, so the city narrows the search to the
      # right branch of a chain.
      def self.location_granularity = :city
      def self.locations_api = "business_data_google"

      def self.trend_metrics
        [
          {key: "rating", label: "Rating", good: "up"},
          {key: "reviews_count", label: "Reviews", good: "up"},
          {key: "total_photos", label: "Photos", good: "up"},
          {key: "issues", label: "Issues", good: "down"}
        ]
      end

      def self.trend_point(data)
        return {} unless data["found"]

        {
          "rating" => data["rating"]&.to_f,
          "reviews_count" => data["reviews_count"].to_i,
          "total_photos" => data["total_photos"].to_i,
          "issues" => Array(data["issues"]).length
        }
      end

      def call
        response = fetch(PATH, task)
        item = Array(response.first&.dig("items")).first

        return {found: false, searched_for: profile.business_name} if item.nil?

        listing = normalize(item)
        listing.merge(found: true, issues: issues(listing, item))
      end

      private

      # place_id is exact; the name is a search. Prefer the former when the
      # profile carries it, because a business name is rarely unique and the
      # wrong listing produces a report that is confidently about someone
      # else's shop.
      def task
        base = locale_params
        return base.merge(place_id: profile.place_id) if profile.place_id.present?
        return base.merge(cid: profile.cid) if profile.cid.present?

        base.merge(keyword: profile.business_name)
      end

      def normalize(item)
        rating = item["rating"] || {}

        {
          title: item["title"].to_s,
          category: item["category"].to_s,
          additional_categories: Array(item["additional_categories"]),
          address: item["address"].to_s,
          phone: item["phone"].to_s,
          url: item["url"].to_s,
          domain: item["domain"].to_s,
          place_id: item["place_id"].to_s,
          cid: item["cid"].to_s,
          description: item["description"].to_s,
          rating: round(rating["value"], 1),
          reviews_count: rating["votes_count"].to_i,
          rating_distribution: item["rating_distribution"] || {},
          total_photos: item["total_photos"].to_i,
          # `current_status` is the field that catches a listing marked
          # temporarily closed by a stale edit — a silent traffic killer.
          current_status: item.dig("work_time", "current_status").to_s,
          work_hours: item.dig("work_time", "work_hours"),
          attributes: item["attributes"] || {},
          place_topics: item["place_topics"] || {},
          services: Array(item["services"]).first(20),
          people_also_search: Array(item["people_also_search"]).first(10).map { |b| b["title"].to_s }
        }
      end

      # Flat list of {severity, message}. Deliberately not filed as
      # Recommendations — a report is a snapshot and re-running it would file
      # the same finding again. See Report::Runnable; promoting these to the
      # findings queue is a human decision.
      def issues(listing, item)
        found = []

        found << issue(:high, "Listing is marked #{listing[:current_status].humanize.downcase}") if closed?(listing)
        found << issue(:high, "No phone number on the listing") if listing[:phone].blank?
        found << issue(:high, "No website link on the listing") if listing[:url].blank?
        found << issue(:medium, "No description") if listing[:description].blank?

        if listing[:description].present? && listing[:description].length < DESCRIPTION_MIN
          found << issue(:low, "Description is only #{listing[:description].length} characters")
        end

        found << issue(:medium, "No secondary categories set") if listing[:additional_categories].empty?
        found << issue(:medium, "Opening hours not set") if listing[:work_hours].blank?

        if listing[:total_photos] < 10
          found << issue(:low, "Only #{listing[:total_photos]} photos — listings with more get more views")
        end

        if listing[:reviews_count] < 10
          found << issue(:medium, "Only #{listing[:reviews_count]} reviews")
        end

        if listing[:rating] && listing[:rating] < 4.0
          found << issue(:high, "Rating is #{listing[:rating]} — below the 4.0 most people filter on")
        end

        if listing[:domain].present? && profile.domain.present? && !same_domain?(listing[:domain])
          found << issue(:high, "Listing points at #{listing[:domain]}, not #{profile.domain}")
        end

        found << issue(:low, "No services listed") if Array(item["services"]).empty?

        found
      end

      def issue(severity, message) = {severity: severity.to_s, message: message}

      def closed?(listing)
        listing[:current_status].present? && !listing[:current_status].casecmp("open").zero?
      end

      def same_domain?(value)
        host = value.to_s.downcase.sub(/\Awww\./, "")
        host == profile.domain.downcase || host.end_with?(".#{profile.domain.downcase}")
      end
    end
  end
end
