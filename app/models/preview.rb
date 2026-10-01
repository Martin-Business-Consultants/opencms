# frozen_string_literal: true

# Draft preview state, keyed by signed tokens.
#
# Flow: a client mints/updates a draft via Api::PreviewDraftsController, which
# keeps the working state in Rails.cache under the token; the Astro site reads
# it back (GET /api/preview_drafts/:token) to render /_preview/<path>. Tokens
# carry only the page id + an expiry — never the data itself — so the cache is
# the source of truth.
module Preview
  TTL = 1.hour
  PURPOSE = :cms_preview

  module_function

  def issue(page_id:)
    token = SecureRandom.urlsafe_base64(24)
    signed = signer.generate({page_id: page_id, token: token}, expires_in: TTL, purpose: PURPOSE)
    {token: signed, expires_at: TTL.from_now}
  end

  def verify(signed_token)
    return nil unless signed_token.is_a?(String) && !signed_token.empty?

    signer.verified(signed_token, purpose: PURPOSE)
  rescue StandardError
    nil
  end

  def write(signed_token, state)
    payload = verify(signed_token)
    return false unless payload

    Rails.cache.write(cache_key(payload), state.deep_stringify_keys, expires_in: TTL)
    true
  end

  def read(signed_token)
    payload = verify(signed_token)
    return nil unless payload

    raw = Rails.cache.read(cache_key(payload))
    raw&.deep_symbolize_keys
  end

  # Where the Astro site renders a draft: /_preview/<path>?preview=<token>
  # under Settings › General's site base URL, or nil when that isn't set.
  def public_url(path, signed_token)
    base = Setting.get("general")["site_base_url"].to_s.strip
    return nil if base.empty?

    "#{base.sub(%r{/\z}, "")}/_preview/#{path}?preview=#{signed_token}"
  end

  def page_id_for(signed_token)
    verify(signed_token)&.fetch("page_id", nil)
  end

  def cache_key(payload)
    "cms:preview:#{payload["token"]}"
  end

  def signer
    Rails.application.message_verifier(:cms_preview)
  end
end
