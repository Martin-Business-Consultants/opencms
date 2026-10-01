# frozen_string_literal: true

module RecurringTasks
  module Recipes
    # Re-runs the reports on a schedule, so the history builds itself.
    #
    # A snapshot nobody takes regularly is just a spot check. The value of
    # this data is the comparison — "we lost the map pack for three of our
    # keywords in April" is a sentence you can only write if something was
    # taking the measurement in April. Left to a person pressing a button,
    # it doesn't happen.
    #
    # Queues rather than runs. Each report can take two minutes; six of them
    # in the dispatcher's thread would hold a worker for a quarter of an hour
    # and time out. Report::RunJob already handles one at a time.
    #
    # Spends money on a timer, which is why it ships DISABLED (every recurring
    # task does) and why `reports` defaults to the two cheapest rather than
    # everything. Turning it on is a deliberate act with a visible cost.
    class ReportRefresh < Recipe
      class << self
        def title = "Refresh reports"

        def description
          "Re-runs the selected DataForSEO reports so trends keep building. " \
          "Each run is charged to your DataForSEO balance."
        end

        # Monday morning: a week's movement, ready before anyone asks.
        def default_cron = "0 5 * * 1"

        def default_params
          {"reports" => "llm_visibility,ranked_keywords"}
        end

        def param_schema
          [
            {name: "reports", label: "Reports (csv)", type: "string",
             help: "Comma-separated subset of: #{Reports::Catalog::KEYS.join(", ")}"}
          ]
        end
      end

      def perform
        return "No DataForSEO credentials configured." unless DataForSeo::Client.configured?

        kinds = requested_kinds
        return "No valid reports selected." if kinds.empty?

        profile = Reports::Profile.load
        queued = []
        skipped = []

        kinds.each do |kind|
          result = Report.queue(kind, profile: profile)
          if result.queued? && !result.skipped?
            queued << kind
          else
            skipped << "#{kind} (#{result.skipped || result.error})"
          end
        end

        summary(queued, skipped)
      end

      private

      def requested_kinds
        str_param(:reports, "")
          .split(",")
          .map { |kind| kind.strip.downcase }
          .select { |kind| Reports::Catalog.known?(kind) }
          .uniq
      end

      def summary(queued, skipped)
        parts = []
        parts << "queued #{queued.length}: #{queued.join(", ")}" if queued.any?
        parts << "skipped #{skipped.join("; ")}" if skipped.any?
        parts.presence&.join(" · ") || "Nothing to do."
      end
    end
  end
end
