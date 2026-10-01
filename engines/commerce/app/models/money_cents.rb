# frozen_string_literal: true

# Prices arrive as whatever a product page showed — "$2,200.00", "2200",
# "1.294,00" is not attempted — and leave as integer cents. Kept as a module
# rather than a Money dependency: two functions is all commerce-by-quote needs.
module MoneyCents
  module_function

  # "$2,200.00" → 220000; 2200 → 220000; 2200.5 → 220050; "" / nil / "call" → nil
  def parse(value)
    return nil if value.nil?
    return (value * 100).round if value.is_a?(Numeric)

    digits = value.to_s.gsub(/[^\d.\-]/, "")
    return nil if digits.empty? || digits == "." || digits == "-"

    (BigDecimal(digits) * 100).round.to_i
  rescue ArgumentError
    nil
  end

  # 220000 → "$2,200.00". Only USD gets a symbol; anything else is "2,200.00 EUR".
  def format(cents, currency = "USD")
    amount = (cents.to_i.abs / 100.0)
    whole, fraction = Kernel.format("%.2f", amount).split(".")
    whole = whole.reverse.scan(/\d{1,3}/).join(",").reverse
    sign  = cents.to_i.negative? ? "-" : ""
    currency.to_s.upcase == "USD" ? "#{sign}$#{whole}.#{fraction}" : "#{sign}#{whole}.#{fraction} #{currency.to_s.upcase}"
  end
end
