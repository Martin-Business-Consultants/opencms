# frozen_string_literal: true

# A record's place in the sitemap, kept in its `seo` JSON column (see
# Sitemap for what each key means). Pages and entries share it; the admin's
# Sitemap page and PATCH /api/sitemap/:source/:id both change it here.
module Sitemapped
  extend ActiveSupport::Concern

  SETTINGS = %w[sitemap_priority sitemap_changefreq noindex nofollow].freeze

  # Only the settings present are touched. A blank value clears one, and so
  # does one that doesn't parse, so "blank means use the default" works
  # without the caller knowing what the default is.
  def change_sitemap_settings(settings)
    settings = settings.to_h.stringify_keys
    seo = self.seo.is_a?(Hash) ? self.seo.dup : {}

    SETTINGS.each do |key|
      next unless settings.key?(key)

      value = Sitemapped.normalize(key, settings[key])
      value.nil? ? seo.delete(key) : seo[key] = value
    end

    self.seo = seo
  end

  # Recorded as "sitemap.entry_updated" whatever the record is: one audit
  # action for a sitemap row, with the row's source alongside.
  def track_sitemap_update(source:)
    Event.record("sitemap.entry_updated", target: self, source: source)
  end

  def self.normalize(key, raw)
    case key
    when "sitemap_priority" then priority(raw)
    when "sitemap_changefreq" then changefreq(raw)
    else boolean(raw)
    end
  end

  # 0.0..1.0, or nil to clear.
  def self.priority(raw)
    return nil if raw.nil? || raw.to_s.strip.empty?

    Float(raw, exception: false)&.clamp(0.0, 1.0)&.round(2)
  end

  def self.changefreq(raw)
    return nil if raw.nil? || raw.to_s.strip.empty?

    Sitemap::CHANGEFREQS.include?(raw.to_s) ? raw.to_s : nil
  end

  def self.boolean(raw)
    return nil if raw.nil? || raw == ""

    ActiveModel::Type::Boolean.new.cast(raw)
  end
end
