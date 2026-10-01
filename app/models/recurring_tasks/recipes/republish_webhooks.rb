# frozen_string_literal: true

module RecurringTasks
  module Recipes
    # Re-emits the `entry.updated` webhook for every published entry in the
    # configured collection (or every published page when `collection_slug`
    # is "pages"). Useful for triggering scheduled rebuilds of static sites
    # that consume the CMS via webhooks.
    class RepublishWebhooks < Recipe
      class << self
        def title       = "Republish webhooks"
        def description = "Re-fires *.updated webhooks across a collection on a schedule. Triggers static-site rebuilds."
        def default_cron   = "0 5 * * 0"  # Sunday 5am
        def default_params = {"collection_slug" => "pages"}

        def param_schema
          [
            {name: "collection_slug", label: "Collection slug", type: "string",
             help: "A collection slug, or `pages` to re-emit page.updated."}
          ]
        end
      end

      def perform
        slug = str_param(:collection_slug, "pages")

        if slug == "pages"
          count = republish_pages
          "Re-emitted page.updated for #{count} published pages."
        else
          collection = Collection.find_by(slug: slug)
          return "Collection #{slug.inspect} not found." unless collection

          count = republish_entries(collection)
          "Re-emitted entry.updated for #{count} published entries in #{slug}."
        end
      end

      private

      def republish_pages
        count = 0
        Page.where(status: "published").find_each do |page|
          page.announce("page.updated")
          count += 1
        end
        count
      end

      def republish_entries(collection)
        count = 0
        collection.entries.where(status: "published").find_each do |entry|
          entry.announce("entry.updated")
          count += 1
        end
        count
      end
    end
  end
end
