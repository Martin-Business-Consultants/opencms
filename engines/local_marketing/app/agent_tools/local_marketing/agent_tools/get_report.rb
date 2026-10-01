# frozen_string_literal: true

# An agent tool for the `read_reports` capability, registered with
# Cms::Plugins.agent_tool. Loaded only when the Agents plugin is installed
# (LocalMarketing::Engine), since it builds on Agents::Tools::Base.
module LocalMarketing
  module AgentTools
    class GetReport < Agents::Tools::Base
      description "One report in full: the normalized result of its latest snapshot. Pass " \
                  "previous: true for the snapshot before it, to compare. Kinds come from " \
                  "list_reports."
      param :kind, desc: "The report kind, e.g. ranked_keywords", required: true
      param :previous, type: "boolean", desc: "The snapshot before the latest, instead of the latest"

      def execute(kind:, previous: false)
        raise ArgumentError, "unknown report #{kind.inspect}" unless Reports::Catalog.known?(kind)

        report = Report.latest_by_kind[kind.to_s]
        raise ArgumentError, "#{kind} has never been run" if report.nil?

        report = report.previous if previous
        return {report: nil, note: "#{kind} has only one snapshot; nothing to compare with"} if report.nil?

        {report: {kind: report.kind, title: report.title, measured_at: report.created_at.iso8601,
                  cost: report.cost.to_f, data: report.data}}
      end
    end
  end
end
