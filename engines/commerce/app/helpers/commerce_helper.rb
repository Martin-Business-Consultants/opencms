# frozen_string_literal: true

module CommerceHelper
  # [["All (12)", nil], ["New (3)", "new"], …] for a status quick filter.
  # [[label, value, count], …] for the list's status links.
  def commerce_status_links(statuses, counts)
    [["All", nil, counts.values.sum]] + statuses.filter_map { |status| [status.humanize, status, counts[status]] if counts[status].to_i.positive? }
  end

  # An amount as people type it back in: "$2,200.00", or blank for nothing.
  # The controller reads it with MoneyCents.parse.
  def money_input_value(cents, currency)
    cents.to_i.zero? ? nil : MoneyCents.format(cents, currency)
  end

  def invoice_line_total(invoice, line)
    invoice.formatted(line["quantity"].to_i * line["unit_price_cents"].to_i)
  end
end
