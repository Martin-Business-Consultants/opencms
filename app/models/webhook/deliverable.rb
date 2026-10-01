# frozen_string_literal: true

require "net/http"
require "openssl"

# Delivering an event to this webhook: POST the envelope, signed with
# HMAC-SHA256 over the request body, and record the attempt in
# `webhook_deliveries`. `deliver_later` queues it (Webhook::DeliveryJob);
# `Webhook.deliver_later` queues it for every active webhook that wants the
# event and whose filter the payload matches.
module Webhook::Deliverable
  extend ActiveSupport::Concern

  PAYLOAD_TRUNCATE  = 16_000
  RESPONSE_TRUNCATE = 4_000
  OPEN_TIMEOUT      = 5
  READ_TIMEOUT      = 10

  class_methods do
    def deliver_later(event, payload)
      for_event(event).find_each do |webhook|
        webhook.deliver_later(event, payload) if webhook.matches_filter?(event, payload)
      end
    end
  end

  def deliver_later(event, payload)
    Webhook::DeliveryJob.perform_later(id, event, payload)
  end

  # A synthetic delivery, so whoever runs the receiving end can check it
  # works without waiting for a real content change.
  def deliver_test
    deliver_later("page.updated", {test: true, message: "Test delivery from CMS"})
    track_event(:test_fired)
  end

  def deliver_now(event, payload)
    return unless active?

    body = JSON.generate(envelope(event, payload))
    started = monotonic_ms
    response, error = post(URI.parse(url), body)
    success = response.is_a?(Net::HTTPSuccess)

    record_delivery(event: event, body: body, response: response, error: error,
      duration: monotonic_ms - started, success: success)
    record_attempt!(success: success)
  end

  private

  # `tenant` keeps its name — receivers (Lumin among them) match on it — and
  # carries Site.key.
  def envelope(event, payload)
    {
      event:        event,
      tenant:       Site.key,
      delivered_at: Time.current.iso8601,
      data:         payload
    }
  end

  def signature_for(body)
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"
  end

  def post(uri, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri, {
      "Content-Type"    => "application/json",
      "User-Agent"      => "mbc-cms-webhooks/1",
      "X-CMS-Signature" => signature_for(body)
    }.merge((headers || {}).to_h.transform_keys(&:to_s)))
    request.body = body

    [http.request(request), nil]
  rescue StandardError => e
    [nil, "#{e.class}: #{e.message}"]
  end

  def record_delivery(event:, body:, response:, error:, duration:, success:)
    deliveries.create!(
      event:           event,
      payload:         body.to_s.first(PAYLOAD_TRUNCATE),
      response_status: response&.code&.to_i,
      response_body:   response&.body.to_s.first(RESPONSE_TRUNCATE),
      error:           error,
      duration_ms:     duration,
      success:         success,
      created_at:      Time.current
    )
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  end
end
