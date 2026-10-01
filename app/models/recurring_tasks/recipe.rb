# frozen_string_literal: true

# Base class for catalog recipes. A recipe is a self-contained unit of
# scheduled work — its class declares its display metadata, default cron,
# parameter schema, and how to execute. Instances are constructed by the
# runner job with the user-configured params and asked to `perform`.
#
# Subclasses must implement `perform` and return a short human-readable
# summary string (or anything `.to_s`-able) — the runner stores it on
# `RecurringTask#last_summary` for display in the UI.
module RecurringTasks
  class Recipe
    class << self
      def key
        name.demodulize.underscore
      end

      def title
        ""
      end

      def description
        ""
      end

      # Cron expression used when a site first enables this recipe.
      def default_cron
        "0 3 * * *"
      end

      # Hash of param defaults, merged with stored params at runtime.
      def default_params
        {}
      end

      # Array of `{name:, label:, type:, help:}` entries describing tunable
      # params. The UI renders an input per entry. Types: string, integer,
      # url, collection_slug.
      def param_schema
        []
      end
    end

    attr_reader :params

    def initialize(params = {})
      @params = ((self.class.default_params || {}).merge(params || {})).with_indifferent_access
    end

    def perform
      raise NotImplementedError, "#{self.class} must implement #perform"
    end

    private

    def int_param(key, default = 0)
      v = params[key]
      v.to_s.match?(/\A-?\d+\z/) ? v.to_i : default
    end

    def str_param(key, default = "")
      v = params[key].to_s
      v.empty? ? default : v
    end
  end
end
