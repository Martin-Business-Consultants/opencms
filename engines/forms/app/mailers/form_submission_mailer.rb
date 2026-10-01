# frozen_string_literal: true

# Single delivery action shared by both notification (admin) and confirmation
# (user) emails. The subject and blocks come from the FormEmail row, with
# placeholders rendered against the submission. The body is the Astro site's
# template for those blocks when its build has sent one, otherwise the CMS's
# own layout (form_submission_mailer/deliver.html.erb): the branding logo,
# the blocks, then a kind-specific footer.
class FormSubmissionMailer < ApplicationMailer
  helper FormEmailBlocksHelper

  DEFAULT_FROM_NAME  = "Forms"
  # Outsend only accepts mail from a domain the account owns, so an
  # unconfigured site falls back to the credentialed sender rather
  # than to an address that would bounce at the relay.
  def self.default_from_email = ApplicationMailer.from_address

  def deliver
    @form_email = params[:form_email]
    @submission = params[:submission]
    @form       = @form_email.form
    recipients  = params[:recipients]

    settings   = Setting.get("forms_settings")
    from_name  = settings["from_name"].presence  || DEFAULT_FROM_NAME
    from_email = settings["from_email"].presence || self.class.default_from_email

    @subject  = @form_email.render(@form_email.subject, @submission)
    @blocks   = @form_email.content_blocks
    @logo_url = compute_logo_url

    headers = {from: "\"#{from_name}\" <#{from_email}>", to: recipients, subject: @subject.presence || default_subject_for(@form_email)}
    # The site's own design once its build has sent a template for these
    # blocks (FormEmail::SiteTemplate); the CMS's layout until then.
    if @form_email.site_template_current?
      html = @form_email.fill_site_template(@submission)
      mail(headers) { |format| format.html { render html: html.html_safe, layout: false } }
    else
      mail(headers)
    end
  end

  private

  def default_subject_for(form_email)
    form_email.notification? ? "[#{@form.title}] New submission ##{@submission.id}" : "Thanks for your submission"
  end

  # Resolve the branding logo to an absolute URL so email clients can fetch
  # it. Pulled from the `branding` Setting; needs Setting.get("general")
  # ["site_base_url"] to build a host-qualified URL. Returns nil if either
  # piece is missing — the layout hides the logo block in that case.
  def compute_logo_url
    branding = Setting.get("branding")
    logo_id  = branding["logo_id"]
    return nil if logo_id.blank?

    asset = Asset.with_attached_file.find_by(id: logo_id)
    return nil unless asset&.file&.attached?

    base = Setting.get("general")["site_base_url"].to_s
    base = base.sub(%r{/+\z}, "")
    return nil if base.empty?

    path = Rails.application.routes.url_helpers.rails_blob_path(asset.file, only_path: true)
    "#{base}#{path}"
  rescue StandardError
    nil
  end
end
