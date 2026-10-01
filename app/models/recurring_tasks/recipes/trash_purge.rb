# frozen_string_literal: true

module RecurringTasks
  module Recipes
    # Hard-deletes records that have been in the trash longer than the
    # configured retention window (Trash.purge_expired). The one purge path:
    # schedule it in Tools › Schedules.
    class TrashPurge < Recipe
      class << self
        def title       = "Trash purge"
        def description = "Permanently deletes records that have been in the trash longer than the retention window."
        def default_cron   = "0 3 * * *"
        def default_params = {"retention_days" => 30}

        def param_schema
          [
            {name: "retention_days", label: "Retention (days)", type: "integer",
             help: "Records discarded longer ago than this are hard-deleted."}
          ]
        end
      end

      def perform
        retention = int_param(:retention_days, 30).clamp(1, 3650)
        purged    = Trash.purge_expired(Time.current - retention.days)

        return "No records past retention." if purged.empty?

        purged.map { |k, v| "#{v} #{k.tableize}" }.join(", ") + " purged."
      end
    end
  end
end
