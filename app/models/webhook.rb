# frozen_string_literal: true

# Outbound webhooks fired when content changes. Designed for the public
# Astro frontend to revalidate on publish (and similar consumers); each
# delivery is signed with HMAC-SHA256 over the request body so the receiver
# can verify it.
#
# Events follow `<resource>.<action>`. The core's are enumerated below; a
# plugin adds its own with `Cms::Plugins.webhook_events`, and Webhook.events is
# the lot. Adding one is a two-step change: list it (here, or in the plugin),
# then `announce` it from the model that produces it (Eventable, Event).
class Webhook < ApplicationRecord
  include EditableHeaders
  include Deliverable
  include Eventable

  # If this webhook points at Lumin, its `secret` must be Lumin's own
  # Site#webhook_secret rather than the one generated here — that is the key the
  # receiver verifies the signature with. See docs/lumin-integration.md.
  EVENTS = %w[
    page.published
    page.updated
    page.unpublished
    page.deleted
    entry.published
    entry.updated
    entry.unpublished
    entry.deleted
    global.updated
  ].freeze

  # The core's events and every installed plugin's, each where its plugin
  # placed it — what a webhook may subscribe to, and what /api/webhooks lists.
  def self.events
    Cms::Plugins.arrange(EVENTS.map { [it, it] }, Cms::Plugins.webhook_event_additions).map(&:first)
  end

  # Events that should trigger a public-site rebuild via the site's deploy
  # hook: every core event (each changes content), and a plugin's only when it
  # says so (`webhook_events … deploy: true`) — a form submission doesn't
  # change the static output.
  def self.deploy_events
    EVENTS + Cms::Plugins.deploy_webhook_events
  end

  # Submitted `event_filters` in the shape each event's filter stores
  # (Cms::Plugins.webhook_event_filter), empty criteria dropped. Anything
  # else is left out, so arbitrary JSON can't be stashed on the record
  # through mass-assignment.
  def self.permitted_event_filters(raw)
    return {} if raw.blank?

    Cms::Plugins.webhook_event_filters.values.reduce({}, :merge).each_with_object({}) do |(event, filter), permitted|
      value = filter.permit.call(raw[event])
      permitted[event] = value if value.present?
    end
  end

  has_many :deliveries,
           class_name: "WebhookDelivery",
           dependent:  :delete_all,
           inverse_of: :webhook

  validates :name, presence: true
  validates :url,  presence: true
  validate  :validate_url
  validate  :validate_events
  validate  :validate_headers
  validate  :validate_event_filters

  before_validation :ensure_secret, on: :create

  scope :ordered, -> { order(:name) }
  scope :active,  -> { where(active: true) }
  scope :for_event, ->(event) {
    # JSON column stored as a string in SQLite — match the quoted token to
    # avoid false positives like "page.update" matching "page.updated".
    active.where("events LIKE ?", "%\"#{event}\"%")
  }

  # Per-event criteria (`event_filters[event]`), as the plugin that owns the
  # event reads them (Cms::Plugins.webhook_event_filter) — Forms narrows
  # submission.created to chosen forms. An event without a registered filter,
  # or a webhook without criteria for it, always fires.
  def matches_filter?(event, payload)
    filter = Cms::Plugins.webhook_event_filter_for(event)
    return true unless filter

    filter.match.call(event_filters.is_a?(Hash) ? event_filters[event] : nil, payload)
  end

  def regenerate_secret!
    update!(secret: self.class.generate_secret)
    track_event(:secret_rotated)
  end

  def self.generate_secret
    "whsec_#{SecureRandom.urlsafe_base64(32)}"
  end

  def record_attempt!(success:, status: nil, error: nil)
    self.last_delivery_at = Time.current
    self.last_status = success ? "success" : "failure"
    self.failure_count = success ? 0 : failure_count + 1
    save!(validate: false)
    [status, error] # convenience for callers that want both
  end

  private

  # Parse rather than pattern-match: requires a real host, so "https://" or
  # "http://#foo" are rejected, not just non-http schemes.
  def validate_url
    return if url.blank?

    uri = URI.parse(url)
    errors.add(:url, "must be an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, "must be an http(s) URL")
  end

  def validate_events
    return errors.add(:events, "must be an array") unless events.is_a?(Array)
    return errors.add(:events, "must include at least one event") if events.empty?

    bad = events - self.class.events
    errors.add(:events, "unknown: #{bad.join(", ")}") if bad.any?
  end

  def validate_headers
    return if headers.is_a?(Hash)

    errors.add(:headers, "must be an object")
  end

  def validate_event_filters
    return errors.add(:event_filters, "must be an object") unless event_filters.is_a?(Hash)

    event_filters.each do |event, value|
      next if value.blank?

      Cms::Plugins.webhook_event_filter_for(event)&.validate&.call(value, errors)
    end
  end

  def ensure_secret
    self.secret ||= self.class.generate_secret
  end
end
