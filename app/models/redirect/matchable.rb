# frozen_string_literal: true

# Two match modes:
#   * exact     — `source_path` must equal the request path verbatim
#   * wildcard  — `source_path` ends with `/*` and matches any subpath; the
#                 captured tail is appended to `destination_url` if the
#                 destination also ends with `/*`.
#
# `Redirect.match(path)` returns `{redirect:, destination:, status:}` or nil.
# Exact matches always win over wildcard matches; among wildcards, the longest
# prefix wins. `Redirect.resolve(path)` is the same look-up for a real request,
# counting the hit.
module Redirect::Matchable
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_source_path
    before_validation :infer_wildcard

    scope :exact,     -> { where(wildcard: false) }
    scope :wildcards, -> { where(wildcard: true) }
  end

  class_methods do
    def match(path)
      return nil if path.blank?

      normalized = normalize_path(path)

      if (exact = active.exact.find_by(source_path: normalized))
        return {redirect: exact, destination: exact.destination_url, status: exact.status_code}
      end

      # Wildcard rules are admin-curated and small in count; an in-memory scan
      # is simpler and faster than building a SQL prefix predicate per dialect.
      rules = active.wildcards.to_a.select { |r| r.matches?(normalized) }
      rule  = rules.max_by { |r| r.source_path.length }
      return nil unless rule

      {redirect: rule, destination: rule.expand(normalized), status: rule.status_code}
    rescue StandardError => e
      Rails.logger.warn("[Redirect.match] #{e.class}: #{e.message}")
      nil
    end

    def resolve(path)
      match(path)&.tap { |found| found[:redirect].record_hit! }
    end

    def normalize_path(path)
      p = path.to_s.strip
      p = "/#{p}" unless p.start_with?("/")
      p = p.chomp("/") if p.length > 1 && p.end_with?("/")
      p
    end
  end

  def matches?(path)
    return source_path == path unless wildcard

    prefix = source_path.delete_suffix("/*")
    path == prefix || path.start_with?("#{prefix}/")
  end

  # Expand a wildcard destination by appending the captured suffix.
  def expand(path)
    return destination_url unless wildcard && destination_url.end_with?("/*")

    prefix = source_path.delete_suffix("/*")
    suffix = path == prefix ? "" : path.sub(/\A#{Regexp.escape(prefix)}/, "")
    destination_url.delete_suffix("/*") + suffix
  end

  def record_hit!
    self.class.where(id: id).update_all(
      "hit_count = hit_count + 1, last_hit_at = #{self.class.connection.quote(Time.current)}"
    )
  end

  private

  def normalize_source_path
    self.source_path = source_path.to_s.strip
    return if source_path.empty?

    self.source_path = "/#{source_path}" unless source_path.start_with?("/")
    if source_path.end_with?("/*")
      base = source_path.delete_suffix("/*")
      base = base.chomp("/")
      self.source_path = "#{base}/*"
    elsif source_path.length > 1 && source_path.end_with?("/")
      self.source_path = source_path.chomp("/")
    end
  end

  def infer_wildcard
    self.wildcard = source_path.to_s.end_with?("/*")
  end

  def validate_wildcards
    if source_path.present? && !wildcard && source_path.include?("*")
      errors.add(:source_path, "wildcard `*` is only allowed as a trailing `/*`")
    end

    if destination_url.present? && destination_url.include?("*") && !destination_url.end_with?("/*")
      errors.add(:destination_url, "wildcard `*` is only allowed as a trailing `/*`")
    end

    if destination_url.to_s.end_with?("/*") && !wildcard
      errors.add(:destination_url, "trailing `/*` requires the source to also end with `/*`")
    end
  end
end
