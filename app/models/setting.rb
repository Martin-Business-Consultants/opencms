# frozen_string_literal: true

# Site-wide admin configuration. Distinct from `Global`, which is for
# editorially-authored singleton content surfaced to the public site (nav,
# footer, business identity). Settings are configuration the public site
# never sees: integration tokens, feature flags, default locale, etc.
#
# Stored as a thin key/value model: `Setting.get("github")` returns a hash;
# `Setting.set("github", token: "ghp_…")` deep-merges into the value.
class Setting < ApplicationRecord
  include Eventable
  include Redactable

  # Provider API keys and the like. They used to sit in the plain `data` JSON
  # column, where a database file, a backup, or a stray `SELECT *` in a
  # console handed someone a working credential. They live here instead,
  # encrypted at rest, and are never round-tripped to a form — a settings page
  # shows "already set, ends in ab12" and nothing more.
  #
  # A JSON blob rather than a column per secret because the set of them is
  # open: every integration this CMS grows brings one, and none of them is
  # ever queried BY value, so there is nothing a column would buy.
  encrypts :secrets

  validates :key, presence: true, uniqueness: true

  scope :ordered, -> { order(:key) }

  def self.get(key)
    find_by(key: key.to_s)&.data || {}
  end

  def self.set(key, attrs)
    record = find_or_initialize_by(key: key.to_s)
    record.data = (record.data || {}).merge(attrs.deep_stringify_keys)
    record.save!
    record
  end

  # Drops names from a setting's data (a value that has moved to `secrets`).
  def self.unset(key, *names)
    record = find_by(key: key.to_s) or return
    record.update!(data: (record.data || {}).except(*names.map(&:to_s)))
  end

  def self.delete_key(key)
    where(key: key.to_s).delete_all
  end

  # --- secrets -------------------------------------------------------------

  # nil for a key that isn't set, and for a settings row that doesn't exist —
  # "no credential" is one answer, and callers should not have to tell the two
  # apart before deciding they have nothing to authenticate with.
  def self.secret(key, name)
    find_by(key: key.to_s)&.secrets_hash&.[](name.to_s).presence
  end

  # Merges, like `set` does. A blank value is a DELETE rather than an empty
  # string: forms send "" for an untouched password field, and a stored ""
  # would read as "configured" everywhere that checks `.present?`.
  def self.set_secret(key, attrs)
    record = find_or_initialize_by(key: key.to_s)
    merged = record.secrets_hash.merge(attrs.deep_stringify_keys)
    merged = merged.reject { |_, value| value.to_s.strip.empty? }
    record.secrets = merged.empty? ? nil : JSON.generate(merged)
    record.save!
    record
  end

  def secrets_hash
    parsed = JSON.parse(secrets.presence || "{}")
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    # Unreadable ciphertext means the key that wrote it is gone. Treat it as
    # "nothing stored" so the app boots and the settings page says "not set",
    # rather than 500ing on every request that reads a credential.
    {}
  end
end
