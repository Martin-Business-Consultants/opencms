# frozen_string_literal: true

# Reports as text: a report's data is a Hash of named figures, lists and
# tables (Reports::Definition keeps it flat and small on purpose), so one
# renderer says what any report found — the charts are being rethought.
module LocalMarketingHelper
  TABLE_ROWS = 100
  TABLE_COLUMNS = 8

  # Keys shown elsewhere on the page, or of no use to a reader.
  HIDDEN_KEYS = %w[warnings narrative].freeze

  def report_money(amount) = number_to_currency(amount.to_f, precision: amount.to_f < 1 ? 3 : 2)

  def report_label(key) = key.to_s.humanize

  # One figure, said plainly: numbers with separators, yes/no, dashes for
  # nothing, links only for web addresses.
  def report_value(value)
    case value
    when nil, "" then "—"
    when true then "Yes"
    when false then "No"
    when Integer then number_with_delimiter(value)
    when Float then number_with_delimiter(value.round(2))
    when Array then report_list(value)
    when Hash then value.map { |k, v| "#{report_label(k)}: #{report_plain(v)}" }.join("; ").truncate(240)
    else report_string(value.to_s)
    end
  end

  def report_list(values)
    values.first(20).map { |v| report_plain(v) }.join(", ").then { |text| values.length > 20 ? "#{text}, and #{values.length - 20} more" : text }
  end

  # A figure's change since the run before, and whether that's good.
  def report_change(metric)
    now, before = metric[:now], metric[:previous]
    return "first measurement" if before.nil?
    return "—" unless now.is_a?(Numeric) && before.is_a?(Numeric)
    return "no change" if now == before

    delta = now - before
    better = metric[:good].to_s == "down" ? delta.negative? : delta.positive?
    "#{delta.positive? ? "up" : "down"} #{number_with_delimiter(delta.abs.round(2))} (#{better ? "better" : "worse"})"
  end

  # The data's parts, sorted into what renders as a figure, a list, a table
  # or a section of its own.
  def report_sections(data, except: [])
    figures, tables, sections = [], [], []
    data.to_h.each do |key, value|
      next if HIDDEN_KEYS.include?(key.to_s) || except.include?(key.to_s)

      if value.is_a?(Array) && value.any? && value.all?(Hash)
        tables << [key.to_s, value]
      elsif value.is_a?(Hash) && value.any?
        sections << [key.to_s, value]
      else
        figures << [key.to_s, value]
      end
    end
    {figures: figures, tables: tables, sections: sections}
  end

  # The keys a report's own partial (reports/kinds/_<kind>) shows, so the
  # generic tables don't repeat them.
  KIND_HANDLES = {"citations" => %w[directories], "site_audit" => %w[findings passed]}.freeze

  def report_kind_handles(kind) = KIND_HANDLES.fetch(kind.to_s, [])

  def report_columns(rows)
    rows.first(50).flat_map { |row| row.keys.map(&:to_s) }.uniq.first(TABLE_COLUMNS)
  end

  private

  def report_plain(value)
    case value
    when Hash then value.map { |k, v| "#{k}: #{v}" }.join(" ")
    when Float then value.round(2).to_s
    else value.to_s
    end
  end

  def report_string(text)
    if text.match?(%r{\Ahttps?://\S+\z})
      link_to text.truncate(80), text, class: "txt-link", rel: "noopener noreferrer nofollow", target: "_blank"
    else
      text.truncate(240)
    end
  end
end
