# frozen_string_literal: true

# "Is anything waiting on me, and how bad is it?" — answered once, for the
# banner, the tiles and the sheet behind them.
#
# The thing worth surfacing here is not the size of the queue. A queue of
# forty is fine if it turned over last week and alarming if the oldest item
# has been sitting for a month, and the count alone can't tell those apart.
# So the dominant fact is **age**, then impact, then volume.
class Recommendation::QueueState
  Item = Struct.new(:severity, :title, :detail, :href, keyword_init: true)

  STALE = 14.days
  VERY_STALE = 30.days
  # Above this the queue has stopped being a queue and become an archive
  # nobody reads, which is its own kind of failure.
  FLOODED = 100

  def initialize(open:, now: Time.current)
    @open = open
    @now = now
  end

  def to_h
    {
      severity: severity,
      headline: headline,
      detail: detail,
      counts: counts.map { |label, value| {label: label, value: value} },
      attention_count: items.count { |item| item.severity != "info" },
      items: items.map { |item| {severity: item.severity, title: item.title, detail: item.detail, href: item.href} }
    }
  end

  def severity
    return "success" if @open.empty?
    return "danger" if very_stale.any? || @open.size >= FLOODED

    stale.any? || high_impact.any? ? "warning" : "info"
  end

  def headline
    return "Nothing is waiting on you" if @open.empty?
    return "#{count_of(very_stale)} #{very_stale.one? ? "has" : "have"} been open over a month" if very_stale.any?
    return "#{@open.size} findings — the queue has stopped turning over" if @open.size >= FLOODED
    return "#{count_of(high_impact)} rated high impact" if high_impact.any?

    "#{@open.size} #{"finding".pluralize(@open.size)} waiting on you"
  end

  def detail
    return "Agents file findings here when they hit something that needs a person." if @open.empty?
    return "A finding nobody has decided is worse than one nobody filed: the agent will keep finding it." if very_stale.any?

    "Deciding one records the decision. It never writes content — that still goes through the ordinary review gate."
  end

  def counts
    [
      ["Open", @open.size],
      ["Needs attention", (very_stale + stale + high_impact).uniq.size],
      ["Actionable", @open.count(&:actionable?)]
    ]
  end

  def items
    @items ||= (
      very_stale.map { |rec| item(rec, "danger", "open #{age_in_days(rec)} days") } +
        stale.map { |rec| item(rec, "warning", "open #{age_in_days(rec)} days") } +
        (high_impact - very_stale - stale).map { |rec| item(rec, "warning", "impact #{rec.impact}") }
    ).first(25)
  end

  private

  def very_stale = @very_stale ||= @open.select { |rec| rec.created_at < @now - VERY_STALE }

  def stale
    @stale ||= @open.select { |rec| rec.created_at.between?(@now - VERY_STALE, @now - STALE) }
  end

  def high_impact = @high_impact ||= @open.select { |rec| rec.impact >= 4 }

  def age_in_days(rec) = ((@now - rec.created_at) / 1.day).floor

  def item(rec, severity, why)
    Item.new(
      severity: severity,
      title: rec.title,
      detail: "#{rec.kind_label} · #{rec.subject_label || "no subject"} · #{why}",
      href: "/recommendations/#{rec.id}"
    )
  end

  def count_of(list) = "#{list.size} #{"finding".pluralize(list.size)}"
end
