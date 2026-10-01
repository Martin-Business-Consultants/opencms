# frozen_string_literal: true

require "net/http"

# Server-side check of a Cloudflare Turnstile token, for the public form
# submission endpoint. The site key / secret key pair is configured on the
# Forms admin page and stored in the `forms_settings` Setting.
#
#   verifier = TurnstileVerifier.from_settings
#   verifier.nil?                       # => no Turnstile secret configured
#   verifier.verify(token, remote_ip:)  # => true / false
#
# Fails closed: a network error or an unparseable answer from Cloudflare is a
# failed verification, because a captcha that passes whenever the verifier is
# unreachable is no captcha at all.
class TurnstileVerifier
  VERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")

  # nil unless a Turnstile secret is set and Turnstile hasn't been switched
  # off in favour of another provider. A secret left behind after choosing
  # "none" or "recaptcha" must not start rejecting submissions from a site
  # that no longer renders the widget.
  def self.from_settings
    settings = Setting.get("forms_settings")
    return nil unless settings["captcha_provider"].blank? || settings["captcha_provider"] == "turnstile"

    secret = Forms.captcha_secret("turnstile_secret_key")
    secret ? new(secret) : nil
  end

  def initialize(secret)
    @secret = secret
  end

  def verify(token, remote_ip: nil)
    return false if token.blank?

    form = {"secret" => @secret, "response" => token.to_s}
    form["remoteip"] = remote_ip if remote_ip.present?

    response = Net::HTTP.start(VERIFY_URL.host, VERIFY_URL.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
      req = Net::HTTP::Post.new(VERIFY_URL.request_uri)
      req.set_form_data(form)
      http.request(req)
    end
    return false unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)["success"] == true
  rescue StandardError => e
    Rails.logger.warn("[forms] turnstile verification error: #{e.class}: #{e.message}")
    false
  end
end
