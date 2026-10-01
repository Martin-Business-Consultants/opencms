# frozen_string_literal: true

# PUT /api/forms/:form_slug/emails/:email_kind/template — the Astro site's
# build sending the email template it made from the email's blocks
# (integrations/astro/emails.ts): {html, digest}. The digest is the
# content_digest of the blocks it was built from; the template is sent only
# while that's still the email's (FormEmail::SiteTemplate).
class Api::FormEmailTemplatesController < Api::BaseController
  include PluginGated
  plugin :forms

  enforce_authorization
  requires_capability "forms:templates", only: :update

  def update
    form = Form.find_by!(slug: params[:form_slug])
    @email = form.emails.find_by!(kind: params[:email_kind])

    @email.receive_site_template!(html: params.require(:html).to_s, digest: params.require(:digest).to_s)
    @email.track_event(:template_received, form: form.slug, kind: @email.kind, status: @email.site_template_status)
  end
end
