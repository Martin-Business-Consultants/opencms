# frozen_string_literal: true

# A request for a price, sent from the public site (or typed in by staff).
#
# `items` is the product as the visitor saw it — title, SKU, listed price,
# URL — captured at the moment of asking, so the request still reads
# correctly after the catalogue changes. A request moves through a small
# status ladder as the shop works it; `Invoice.from_quote_request` turns it
# into a bill once a price is agreed.
class QuoteRequest < ApplicationRecord
  include ListSearchable

  search_on :customer_name, :customer_email, :company, :message

  include Eventable
  include Notifiable

  STATUSES = %w[new quoted invoiced won lost archived].freeze
  SOURCES  = %w[site manual api].freeze
  ITEM_KEYS = %w[title slug sku url unit_price quantity].freeze

  has_many :invoices, dependent: :nullify

  validates :customer_name, presence: true
  validates :status, inclusion: {in: STATUSES}
  validates :source, inclusion: {in: SOURCES}
  validates :customer_email, format: {with: URI::MailTo::EMAIL_REGEXP}, allow_blank: true
  validate  :validate_contact
  validate  :validate_items

  before_validation :normalize

  after_create_commit :enqueue_notification
  after_create_commit :emit_created_webhook

  scope :ordered, -> { order(created_at: :desc) }
  scope :open,    -> { where(status: %w[new quoted invoiced]) }

  def self.status_counts
    group(:status).count
  end

  # One line a person can scan an inbox by: the first item's title and how
  # many more there are, else the start of the message.
  def summary
    first = items.first
    return message.to_s.truncate(120) if first.nil?

    rest = items.size - 1
    base = first["title"].to_s
    base += " +#{rest} more" if rest.positive?
    base
  end

  def webhook_payload
    {
      id:             id,
      status:         status,
      source:         source,
      customer_name:  customer_name,
      customer_email: customer_email,
      customer_phone: customer_phone,
      company:        company,
      message:        message,
      items:          items,
      page_url:       page_url,
      created_at:     created_at&.iso8601
    }
  end

  private

  def normalize
    self.customer_name  = customer_name.to_s.strip
    self.customer_email = customer_email.to_s.strip.downcase.presence
    self.customer_phone = customer_phone.to_s.strip.presence
    self.company        = company.to_s.strip.presence
    self.items = Array(items).filter_map { |raw|
      next unless raw.is_a?(Hash)

      item = raw.stringify_keys.slice(*ITEM_KEYS)
      next if item["title"].to_s.strip.empty?

      item["title"]    = item["title"].to_s.strip
      item["quantity"] = [item["quantity"].to_i, 1].max
      item["unit_price"] = item["unit_price"].to_s.strip.presence
      item.compact
    }
  end

  # An email or a phone number: the shop has to be able to answer.
  def validate_contact
    return if customer_email.present? || customer_phone.present?

    errors.add(:base, "an email address or a phone number is required")
  end

  def validate_items
    errors.add(:items, "must be a list") unless items.is_a?(Array)
    errors.add(:items, "cannot exceed 50 lines") if items.is_a?(Array) && items.size > 50
  end

  def enqueue_notification
    notify_later
  end

  def emit_created_webhook
    announce("quote_request.created")
  end
end
