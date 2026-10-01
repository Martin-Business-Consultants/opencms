# frozen_string_literal: true

# "Send me a test": the email as saved, for a made-up submission, to the
# person asking.
class FormEmails::TestsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "forms:write", only: :create

  def create
    form = Form.find_by!(slug: params[:form_slug])
    email = form.emails.find_by!(kind: params[:email_kind])
    FormSubmissionMailer.with(form_email: email, submission: FormEmail::Sample.submission(form),
      recipients: [Current.user.email]).deliver.deliver_now

    redirect_to edit_form_email_path(form_slug: form.slug, kind: email.kind), notice: "Test sent to #{Current.user.email}"
  end
end
