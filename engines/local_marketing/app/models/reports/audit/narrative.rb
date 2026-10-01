# frozen_string_literal: true

module Reports
  module Audit
    # Three sentences about the audit, for the top of the report and the
    # dashboard card, written by the cheap model tier — DeepSeek V4 Flash
    # on Zen today.
    #
    # The rule is the same as the Marketer's Report: the model writes about
    # facts it was handed and never adds one. It is told the findings and the
    # passes as titles and severities and asked which to fix first and why;
    # it is not asked to find anything. Absent when no key is configured, and
    # the report is complete without it.
    module Narrative
      SCHEMA = {
        type: "object",
        required: %w[summary],
        properties: {
          summary: {type: "string", description: "Two or three plain sentences for the marketer who runs this site. Name only findings from the list, by their titles. No numbers that aren't in the list, no headings."},
          first_fix: {type: "string", description: "One sentence: which single finding to fix first and why it matters to a local business."}
        }
      }.freeze

      module_function

      def call(findings:, passed:, business:)
        # A model, when the AI plugin is on and has a key (Cms::Plugins.provided).
        ai = Cms::Plugins.provided(:ai)
        return nil unless ai&.configured?

        answer = ai.oneshot(purpose: "site audit narrative", prompt: prompt(findings, passed, business), schema: SCHEMA, model: "cheap")
        return nil if answer.nil? || answer["summary"].blank?

        {summary: answer["summary"].to_s.strip, first_fix: answer["first_fix"].to_s.strip.presence,
         model: ai.model_for("cheap"), generated_at: Time.current.iso8601}
      end

      def prompt(findings, passed, business)
        <<~PROMPT
          You are summarising a technical audit of the website of #{business.presence || "a local business"} for the marketer who manages it.
          Be plain, specific and brief. Refer to findings by their titles. Do not invent findings, causes or numbers.

          Findings (severity — title):
          #{findings.first(15).map { |f| "- #{f[:severity]} — #{f[:title]}" }.join("\n").presence || "- none"}

          Checks that passed:
          #{passed.first(10).map { |p| "- #{p[:title]}" }.join("\n").presence || "- none"}
        PROMPT
      end
    end
  end
end
