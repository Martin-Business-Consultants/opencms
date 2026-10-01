# frozen_string_literal: true

# ContentValidators provides shared validation helpers for Page and
# CollectionEntry (frontmatter, category/tag pools, scheduled publish, and the
# JSON-LD a page ships in its <script type="application/ld+json">).
module ContentValidators
  extend ActiveSupport::Concern

  included do
    validate :validate_unpublish_after_publish
    validate :validate_seo_json_ld
  end

  private

  def validate_unpublish_after_publish
    return unless publish_at.present? && unpublish_at.present?
    return if unpublish_at > publish_at

    errors.add(:unpublish_at, "must be after the scheduled publish time")
  end

  # Malformed JSON-LD fails silently on the public site (the rich result just
  # never appears), so it's refused here: one node or a list of nodes, each an
  # object with an @type, or an @graph wrapper holding them.
  def validate_seo_json_ld
    return unless seo.is_a?(Hash) && seo.key?("json_ld")

    json_ld = seo["json_ld"]
    return if json_ld.nil?

    nodes = json_ld.is_a?(Array) ? json_ld : [json_ld]
    if nodes.any? { !it.is_a?(Hash) }
      errors.add(:seo, "json_ld must be an object or a list of objects")
    elsif nodes.any? { !it.key?("@type") && !it["@graph"].is_a?(Array) }
      errors.add(:seo, "json_ld: every node needs an @type")
    end
  end
end
