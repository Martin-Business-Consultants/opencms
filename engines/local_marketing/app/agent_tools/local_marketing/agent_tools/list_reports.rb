# frozen_string_literal: true

# An agent tool for the `read_reports` capability, registered with
# Cms::Plugins.agent_tool. Loaded only when the Agents plugin is installed
# (LocalMarketing::Engine), since it builds on Agents::Tools::Base.
module LocalMarketing
  module AgentTools
    class ListReports < Agents::Tools::Base
      description "The latest reporting snapshot of each kind — what search, Google Maps, " \
                  "reviews and the AI assistants show about this business — with each one's " \
                  "headline figures and how they moved since the run before. Read this to " \
                  "decide which report is worth opening in full."

      def execute
        latest = Report.latest_by_kind
        {reports: Reports::Catalog.all.filter_map do |definition|
          report = latest[definition.key] or next nil
          previous = report.previous
          {
            kind: definition.key, title: definition.title, group: definition.group,
            measured_at: report.created_at.iso8601, previous_at: previous&.created_at&.iso8601,
            metrics: report.metrics(against: previous),
            warnings: report.data["warnings"]
          }
        end}
      end
    end
  end
end
