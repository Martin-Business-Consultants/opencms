# frozen_string_literal: true

# Where a content record lives on the published site.
#
# Three things need to agree on this and used to compute it separately: the
# sitemap, the preview link, and the content webhooks. They must agree, because
# the consumer on the other end of the webhook (Lumin) joins Search Console rows
# to CMS records *by URL* — a webhook that announces a different URL than the
# sitemap published is a record the analytics side can never match. See
# ../ads/docs/cms-contract.md.
#
# The including class provides `default_public_path`; an SEO canonical overrides
# it, since a canonical is by definition the address we want to be known by.
# The admin SEO panel saves it as `seo["canonical_url"]`; `seo["canonical"]` is
# still read as a fallback for records written before that key settled.
module PubliclyAddressable
  extend ActiveSupport::Concern

  # Site-relative, with a leading slash: "/about", "/blog/hello".
  def public_path
    seo_canonical.presence || default_public_path
  end

  # Absolute, using the site's configured public origin. Falls back to the
  # relative path when no origin is set rather than inventing one — a wrong
  # absolute URL is worse than an honest relative one, because the consumer
  # can't tell it's wrong.
  def public_url
    path = public_path
    return path if path.to_s.start_with?("http://", "https://")

    base = self.class.site_base_url
    return path if base.blank?

    "#{base.chomp("/")}#{path}"
  end

  private

  def seo_canonical
    seo_hash["canonical_url"].to_s.strip.presence || seo_hash["canonical"].to_s.strip
  end

  def seo_hash
    respond_to?(:seo) && seo.is_a?(Hash) ? seo : {}
  end

  class_methods do
    def site_base_url
      Setting.get("general")["site_base_url"].to_s.strip
    end
  end
end
