# frozen_string_literal: true

# What the shop sends once a price is agreed: line items, totals, and the
# link where the customer pays. The CMS never moves money — `payment_link`
# is whatever the shop's processor issued (a Stripe payment link, a Square
# checkout, a PayPal.me URL) and the hosted page just puts it in front of
# the customer.
#
# Amounts are integer cents. Totals are recomputed from the line items on
# every save so the stored figures can never disagree with the lines.
class Invoice < ApplicationRecord
  include ListSearchable

  search_on :number, :customer_name, :customer_email, :company

  include Eventable
  include Deliverable

  STATUSES = %w[draft sent paid void].freeze
  LINE_KEYS = %w[description sku quantity unit_price_cents].freeze
  DEFAULT_PREFIX = "INV"

  belongs_to :quote_request, optional: true

  validates :customer_name, presence: true
  validates :status, inclusion: {in: STATUSES}
  validates :currency, presence: true, length: {is: 3}
  validates :customer_email, format: {with: URI::MailTo::EMAIL_REGEXP}, allow_blank: true
  # The whole value, anchored at both ends: a link with a line break or a
  # space in it is not a link a customer can click.
  validates :payment_link, format: {with: %r{\Ahttps?://\S+\z}i, message: "must be an http(s) URL"}, allow_blank: true
  validates :number, presence: true, uniqueness: true
  validates :token,  presence: true, uniqueness: true
  validate  :validate_line_items

  before_validation :assign_number, on: :create
  before_validation :assign_token,  on: :create
  before_validation :normalize
  before_validation :recompute_totals

  scope :ordered, -> { order(created_at: :desc) }

  # The sequence lives in the commerce Setting so the shop can pick a prefix
  # and a starting number ("INV-1001") without a migration.
  def self.settings = Setting.get("commerce")

  def self.next_number
    prefix = settings["invoice_prefix"].to_s.strip.presence || DEFAULT_PREFIX
    start  = settings["invoice_next_number"].to_i
    last   = where("number LIKE ?", "#{prefix}-%").maximum(:number)
    seq    = [last.to_s.split("-").last.to_i + 1, start, 1].max
    format("%s-%04d", prefix, seq)
  end

  # A new draft with the shop's defaults: currency, terms, issued today, due
  # after the shop's usual number of days. Nothing is saved.
  def self.drafted(**attributes)
    new(
      currency:  (settings["currency"].presence || "USD"),
      terms:     settings["default_terms"].to_s.presence,
      issued_on: Date.current,
      due_on:    Date.current + (settings["due_days"].presence || 14).to_i.days,
      **attributes
    )
  end

  # Prefills a draft from a quote request: customer as given, one line per
  # item at the price the visitor saw. Nothing is saved — the caller shows the
  # draft for editing, or persists it as-is over the API.
  def self.from_quote_request(quote)
    drafted(
      quote_request:  quote,
      customer_name:  quote.customer_name,
      customer_email: quote.customer_email,
      customer_phone: quote.customer_phone,
      company:        quote.company,
      line_items:     quote.items.map { |item|
        {
          "description"      => item["title"],
          "sku"              => item["sku"],
          "quantity"         => item["quantity"] || 1,
          "unit_price_cents" => MoneyCents.parse(item["unit_price"]) || 0
        }
      }
    )
  end

  def draft? = status == "draft"
  def sent?  = status == "sent"
  def paid?  = status == "paid"
  def void?  = status == "void"

  def sendable?
    !void? && !paid? && customer_email.present? && line_items.any?
  end

  # Marks the invoice as sent and delivers the email. Re-sending a sent
  # invoice is allowed — a customer who lost the email should get it again.
  def send!(base_url:)
    raise ArgumentError, "an invoice needs a customer email and at least one line to be sent" unless sendable?

    update!(status: "sent", sent_at: Time.current, issued_on: issued_on || Date.current)
    deliver_later(base_url)
    quote_request&.update(status: "invoiced") if quote_request&.status.in?(%w[new quoted])
    announce("invoice.sent")
    track_event(:sent, to: customer_email)
  end

  def mark_paid!
    update!(status: "paid", paid_at: Time.current)
    quote_request&.update(status: "won")
    announce("invoice.paid")
    track_event(:paid)
  end

  def void!
    update!(status: "void", voided_at: Time.current)
    track_event(:voided)
  end

  def public_path = "/i/#{token}"

  def formatted(cents) = MoneyCents.format(cents, currency)

  def webhook_payload
    {
      id:             id,
      number:         number,
      status:         status,
      customer_name:  customer_name,
      customer_email: customer_email,
      total_cents:    total_cents,
      currency:       currency,
      payment_link:   payment_link,
      quote_request_id: quote_request_id,
      public_path:    public_path,
      sent_at:        sent_at&.iso8601,
      paid_at:        paid_at&.iso8601
    }
  end

  private

  def assign_number
    self.number = self.class.next_number if number.blank?
  end

  def assign_token
    self.token = SecureRandom.urlsafe_base64(24) if token.blank?
  end

  def normalize
    self.currency = currency.to_s.upcase.presence || "USD"
    self.customer_email = customer_email.to_s.strip.downcase.presence
    self.payment_link = payment_link.to_s.strip.presence
    self.line_items = Array(line_items).filter_map { |raw|
      next unless raw.is_a?(Hash)

      line = raw.stringify_keys
      description = line["description"].to_s.strip
      next if description.empty?

      cents = line.key?("unit_price_cents") ? line["unit_price_cents"].to_i : MoneyCents.parse(line["unit_price"]).to_i
      {
        "description"      => description,
        "sku"              => line["sku"].to_s.strip.presence,
        "quantity"         => [line["quantity"].to_i, 1].max,
        "unit_price_cents" => cents
      }.compact
    }
  end

  def recompute_totals
    self.subtotal_cents = line_items.sum { |l| l["quantity"].to_i * l["unit_price_cents"].to_i }
    self.tax_cents      = tax_cents.to_i
    self.shipping_cents = shipping_cents.to_i
    self.total_cents    = subtotal_cents + tax_cents + shipping_cents
  end

  def validate_line_items
    errors.add(:line_items, "must be a list") unless line_items.is_a?(Array)
    errors.add(:line_items, "cannot exceed 100 lines") if line_items.is_a?(Array) && line_items.size > 100
  end
end
