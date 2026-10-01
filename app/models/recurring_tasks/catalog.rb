# frozen_string_literal: true

# Registry of available recurring task recipes: the core's, and those of
# enabled plugins (Cms::Plugins.recurring_recipe) where they said to sit.
# Recipes are Ruby classes, so adding one is a code change. UI is sourced
# entirely from this catalog.
module RecurringTasks
  module Catalog
    RECIPES = [
      Recipes::TrashPurge,
      Recipes::BrokenLinkScan,
      Recipes::RepublishWebhooks,
      Recipes::SitemapPing,
      Recipes::AssetUsageAudit,
      Recipes::ContentFreshnessReport
    ].freeze

    module_function

    def all
      additions = Cms::Plugins.enabled_recurring_recipes.map { |entry| [entry.klass.key, entry.klass, entry.after] }
      Cms::Plugins.arrange(RECIPES.map { [it.key, it] }, additions).map(&:last)
    end

    def known?(key)
      by_key.key?(key.to_s)
    end

    def by_key = all.index_by(&:key)

    # Returns a recipe instance for a given task row.
    def fetch(key, params = {})
      klass = recipe_class(key)
      raise ArgumentError, "unknown recipe #{key.inspect}" unless klass

      klass.new(params)
    end

    def recipe_class(key)
      by_key[key.to_s]
    end
  end
end
