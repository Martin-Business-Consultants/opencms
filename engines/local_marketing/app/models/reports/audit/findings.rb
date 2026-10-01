# frozen_string_literal: true

module Reports
  module Audit
    # Where the analyzers put what they found.
    #
    # A finding is one thing wrong, with a severity, in words a marketer can
    # act on, and — wherever the fix is inside the CMS — a link to the page
    # that fixes it. A pass is one thing checked and found right; the report
    # lists those too, because "we checked and it's fine" is worth more to a
    # client than silence.
    class Findings
      SEVERITIES = %w[critical high medium low].freeze
      ORDER = SEVERITIES.each_with_index.to_h.freeze
      AREAS = %w[consent tracking calls forms search pages].freeze

      attr_reader :findings, :passed

      def initialize
        @findings = []
        @passed = []
      end

      # `fix` is {label:, href:} for a fix inside the CMS, or {label:} alone
      # when the change is in the site's own code and the body says what.
      def add(key:, area:, severity:, title:, body:, fix: nil, evidence: nil)
        raise ArgumentError, "unknown severity #{severity}" unless SEVERITIES.include?(severity.to_s)
        raise ArgumentError, "unknown area #{area}" unless AREAS.include?(area.to_s)

        @findings << {
          key: key.to_s, area: area.to_s, severity: severity.to_s,
          title: title, body: body, fix: fix, evidence: evidence
        }.compact
      end

      def pass(key:, area:, title:, evidence: nil)
        @passed << {key: key.to_s, area: area.to_s, title: title, evidence: evidence}.compact
      end

      def sorted = @findings.sort_by { |f| [ORDER.fetch(f[:severity], 9), f[:area], f[:title]] }

      def counts
        SEVERITIES.index_with { |s| @findings.count { |f| f[:severity] == s } }
      end
    end
  end
end
