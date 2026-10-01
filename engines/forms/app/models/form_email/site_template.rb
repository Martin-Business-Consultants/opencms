# frozen_string_literal: true

# The email template the Astro site built from this email's blocks, pushed to
# PUT /api/forms/:slug/emails/:kind/template by the site's build
# (integrations/astro/emails.ts). It's the site's own design with the
# {{tokens}} left in; the CMS fills them per submission and sends it. It's
# used only while it was built from the blocks the email has now (its digest
# matches content_digest); until the next build lands, the CMS draws the
# blocks itself.
#
# The template marks where the answers go with one row the CMS repeats per
# answer, holding {{answer.label}} and {{answer.value}}:
#
#   <tr data-cms-repeat="answers"><td>{{answer.label}}</td><td>{{answer.value}}</td></tr>
module FormEmail::SiteTemplate
  extend ActiveSupport::Concern

  REPEAT = "data-cms-repeat"

  def receive_site_template!(html:, digest:)
    update!(site_template: html.to_s, site_template_digest: digest.to_s, site_template_received_at: Time.current)
  end

  # :current (sent as is), :stale (built from older blocks), or :none.
  def site_template_status
    return :none if site_template.blank?

    site_template_digest == content_digest ? :current : :stale
  end

  def site_template_current? = site_template_status == :current

  # The site's template for one submission: answers repeated, tokens filled
  # (their values HTML-escaped).
  def fill_site_template(submission)
    document = Nokogiri::HTML5(site_template.to_s)
    document.css("[#{REPEAT}='answers']").each do |row|
      skip_empty = row["data-cms-skip-empty"] == "true"
      FormEmail::Answers.for(form, submission, skip_empty: skip_empty).each do |label, value|
        copy = row.dup
        copy.remove_attribute(REPEAT)
        copy.remove_attribute("data-cms-skip-empty")
        copy.inner_html = copy.inner_html
          .gsub(/\{\{\s*answer\.label\s*\}\}/) { ERB::Util.h(label) }
          .gsub(/\{\{\s*answer\.value\s*\}\}/) { ERB::Util.h(value) }
        row.add_previous_sibling(copy)
      end
      row.remove
    end
    FormTokens.render_html(form, document.to_html, submission)
  end
end
