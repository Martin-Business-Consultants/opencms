# frozen_string_literal: true

# One of a form's two emails (FormEmail): the notification to the site's own
# people, or the confirmation to whoever submitted. Both are created with the
# form and go with it, so there is only edit and update. A change to its
# blocks schedules a site rebuild, so the Astro site builds a template for
# them (FormEmail::SiteTemplate).
class FormEmailsController < ApplicationController
  include PluginGated
  include FormEmails::Editing
  plugin :forms

  requires_capability "forms:write", only: [:edit, :update]

  before_action { @email = @form.emails.find_by!(kind: params[:kind]) }

  def edit
  end

  def update
    if @email.update(email_attributes(@email))
      @email.track_event(:updated, form: @form.slug, kind: @email.kind, enabled: @email.enabled)
      Deploys.schedule_later(reason: "form_email.updated") if @email.saved_change_to_blocks?
      redirect_to edit_form_email_path(form_slug: @form.slug, kind: @email.kind),
        notice: "#{@email.kind.capitalize} email saved"
    else
      render :edit, status: :unprocessable_content
    end
  end
end
