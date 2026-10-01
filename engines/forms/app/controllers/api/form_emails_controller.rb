# frozen_string_literal: true

# The two email templates hanging off a form — `notification` (to the site
# owner on each submission) and `confirmation` (auto-reply to whoever
# submitted). Rows are created and destroyed with the parent form, so this
# only reads and updates.
#
#   GET   /api/forms/:form_slug/emails
#   GET   /api/forms/:form_slug/emails/:kind
#   PATCH /api/forms/:form_slug/emails/:kind
#
# The response carries `available_tokens` because the templates are
# {{placeholder}} strings and the valid set depends on the form's own
# fields — an agent shouldn't have to infer it from a 422.
class Api::FormEmailsController < Api::BaseController
  include PluginGated
  plugin :forms

  enforce_authorization
  requires_capability "forms:read",  only: [:index, :show]
  requires_capability "forms:write", only: [:update]

  before_action :find_form
  before_action :find_email, only: [:show, :update]

  def index
    @available_tokens = available_tokens
  end

  def show
    @available_tokens = available_tokens
  end

  def update
    @email.update!(email_params)
    @email.track_event(:updated, form: @form.slug, kind: @email.kind, enabled: @email.enabled)
    Deploys.schedule_later(reason: "form_email.updated") if @email.saved_change_to_blocks?
  end

  private

  def find_form
    @form = Form.find_by!(slug: params[:form_slug])
  end

  def find_email
    kind = params[:kind].to_s
    unless FormEmail::KINDS.include?(kind)
      message = "Unknown email kind #{kind.inspect} — expected one of #{FormEmail::KINDS.join(", ")}"
      return render json: {error: "not_found", message: message}, status: :not_found
    end

    @email = @form.emails.find_by!(kind: kind)
  end

  # Blocks come as the JSON array the API returns (FormEmail::BlockTypes).
  def email_params
    permitted = params.require(:form_email).permit(:enabled, :subject, :body, :from_field, :recipients)
    blocks = params[:form_email][:blocks]
    permitted[:blocks] = Array(blocks).map { it.respond_to?(:to_unsafe_h) ? it.to_unsafe_h : it } unless blocks.nil?
    permitted
  end

  # The substitutions FormEmail#render understands: every field on the form,
  # plus the fixed special tokens.
  def available_tokens
    field_tokens = @form.fields.filter_map { |f| f["name"] if f.is_a?(Hash) }
    field_tokens + %w[form_title submission_id submitted_at ip]
  end
end
