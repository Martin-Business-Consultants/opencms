# frozen_string_literal: true

# Drawing a form email's blocks in the CMS's own email layout
# (form_submission_mailer/_blocks), for the preview and for mail sent before
# the Astro site has built its template.
module FormEmailBlocksHelper
  TEXT_TAGS = %w[p br strong b em i u s a ul ol li blockquote h2 h3 h4 code pre].freeze
  TEXT_ATTRIBUTES = %w[href title].freeze

  # Plain text with its {{tokens}} filled, escaped.
  def email_text(text, form, submission)
    FormTokens.render_html(form, ERB::Util.h(text.to_s), submission).html_safe
  end

  # Rich text cut to what mail clients show, with its tokens filled.
  def email_rich_text(html, form, submission)
    safe = sanitize(html.to_s, tags: TEXT_TAGS, attributes: TEXT_ATTRIBUTES)
    FormTokens.render_html(form, safe, submission).html_safe
  end

  def email_accent
    Branding.current.primary_color || "#1c1917"
  end

  def email_asset_url(asset_id) = FormEmail::BlockTypes.asset_url(asset_id)
end
