# frozen_string_literal: true

module RecurringTasks
  module Recipes
    # Surfaces stale published content — pages and entries whose
    # `updated_at` is older than the configured threshold. Returns a
    # summary count; full list to the logs.
    class ContentFreshnessReport < Recipe
      class << self
        def title       = "Content freshness report"
        def description = "Lists published pages and entries that haven't been touched in a while."
        def default_cron   = "0 8 1 * *"  # 1st of each month, 8am
        def default_params = {"min_age_days" => 180}

        def param_schema
          [
            {name: "min_age_days", label: "Stale after (days)", type: "integer",
             help: "Pages or entries published-and-untouched longer than this are flagged."}
          ]
        end
      end

      def perform
        days   = int_param(:min_age_days, 180).clamp(1, 3650)
        cutoff = Time.current - days.days

        stale_pages   = Page.where(status: "published").where("updated_at <= ?", cutoff).pluck(:path)
        stale_entries = CollectionEntry.where(status: "published").where("updated_at <= ?", cutoff).pluck(:slug)

        if stale_pages.empty? && stale_entries.empty?
          return "Nothing older than #{days} days."
        end

        Rails.logger.info("[freshness] pages=#{stale_pages.size} entries=#{stale_entries.size}")

        "#{stale_pages.size} stale page(s), #{stale_entries.size} stale entry(s) older than #{days} days."
      end
    end
  end
end
