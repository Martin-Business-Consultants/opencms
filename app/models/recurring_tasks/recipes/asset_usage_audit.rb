# frozen_string_literal: true

module RecurringTasks
  module Recipes
    # Finds Assets that no ContentReference points at — candidates for
    # cleanup or archival. Reports the count + the first N orphan ids in
    # the run summary; full list goes to the logs.
    class AssetUsageAudit < Recipe
      class << self
        def title       = "Asset usage audit"
        def description = "Counts unreferenced assets so you can spot cleanup candidates."
        def default_cron   = "0 7 * * 1"  # Monday 7am
        def default_params = {"sample_size" => 10}

        def param_schema
          [
            {name: "sample_size", label: "Sample size in summary", type: "integer",
             help: "How many orphan IDs to surface in the inline summary."}
          ]
        end
      end

      def perform
        referenced = ContentReference.where(ref_type: "asset").distinct.pluck(:ref_id).map(&:to_i).to_set
        total      = Asset.count
        orphans    = Asset.where.not(id: referenced.to_a).pluck(:id)

        return "All #{total} assets are referenced." if orphans.empty?

        sample = orphans.first(int_param(:sample_size, 10).clamp(1, 100))
        Rails.logger.info("[asset-usage-audit] orphan_count=#{orphans.size} ids=#{orphans.inspect}")

        "#{orphans.size}/#{total} assets unreferenced. Sample: #{sample.join(", ")}"
      end
    end
  end
end
