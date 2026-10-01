# frozen_string_literal: true

module RecurringTasks
  module Recipes
    # Counts new form submissions in the trailing window and writes a one-
    # line summary per form. The summary is the recipe's last_summary on
    # the task row; richer reporting (email digest etc.) is a follow-up.
    class SubmissionDigest < Recipe
      class << self
        def title       = "Form submission digest"
        def description = "Counts new submissions per form in the trailing window — useful as an at-a-glance pulse."
        def default_cron   = "0 9 * * *"
        def default_params = {"window_hours" => 24}

        def param_schema
          [
            {name: "window_hours", label: "Window (hours)", type: "integer",
             help: "Counts submissions created within the last N hours."}
          ]
        end
      end

      def perform
        hours  = int_param(:window_hours, 24).clamp(1, 24 * 30)
        cutoff = Time.current - hours.hours

        counts = FormSubmission
          .joins(:form)
          .where("form_submissions.created_at >= ?", cutoff)
          .group("forms.slug")
          .count

        return "No submissions in the last #{hours}h." if counts.empty?

        counts.map { |slug, n| "#{slug}=#{n}" }.join(" · ")
      end
    end
  end
end
