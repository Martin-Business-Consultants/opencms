# frozen_string_literal: true

# The headline figures a report's definition picks out (trend_metrics), now
# and at a run to compare with — what the index, the report page and the API
# all show about how it moved.
module Report::Trended
  def metrics(against: previous)
    return [] if definition.nil?

    now = definition.trend_point(data)
    before = against && definition.trend_point(against.data)
    definition.trend_metrics.map do |metric|
      {key: metric[:key], label: metric[:label], good: metric[:good], now: now[metric[:key]], previous: before&.dig(metric[:key])}
    end
  end
end
