# frozen_string_literal: true

# Forms: the forms a site renders and posts to /api/forms/:slug/submissions.
# Export, import and bulk delete are resources under Forms::; the sender and
# spam-protection settings live in Settings › Forms (Settings::FormsController).
class FormsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "forms:read",   only: [:index, :show]
  requires_capability "forms:write",  only: [:new, :create, :edit, :update]
  requires_capability "forms:delete", only: [:destroy]

  before_action :set_form, only: [:show, :edit, :update, :destroy]

  def index
    @forms = Form.ordered.search_list(search_term).to_a
    @submission_counts = FormSubmission.where(form_id: @forms.map(&:id)).group(:form_id).count
    @last_submissions = FormSubmission.where(form_id: @forms.map(&:id)).group(:form_id).maximum(:created_at)
  end

  # The list with its New form sheet open.
  def new
    @new_form = Form.new(status: "draft", submit_label: "Submit")
    index
    render :index
  end

  # From a template (params[:template], a Form::TEMPLATES key) or blank; a
  # template fills in whatever the person left empty.
  def create
    @form = Form.new(create_params)
    apply_template(@form, params[:template])

    if @form.save
      @form.track_event(:created, slug: @form.slug)
      redirect_to edit_form_path(@form.slug), notice: "Form created — add fields and configure"
    else
      @new_form = @form
      index
      render :index, status: :unprocessable_content
    end
  end

  def show
    @submissions = @form.submissions.order(created_at: :desc).limit(50).to_a
    @submission_count = @form.submissions.count
  end

  def edit
  end

  # The slug stays as it is: it's the API key the site posts submissions to.
  def update
    if @form.update(update_params)
      @form.track_event(:updated, slug: @form.slug)
      redirect_to edit_form_path(@form.slug), notice: "Form saved"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @form.track_event(:deleted, slug: @form.slug)
    @form.discard!
    redirect_to forms_path, notice: "Form moved to trash"
  end

  private

  def set_form
    @form = Form.find_by!(slug: params[:slug])
  end

  def create_params
    params.require(:form).permit(:title, :slug, :status, :submit_label)
  end

  def update_params
    permitted = params.require(:form).permit(:title, :status, :submit_url, :submit_label, :success_message, :notify_webhook_url)
    permitted[:submit_url] = permitted[:submit_url].presence if permitted.key?(:submit_url)
    permitted[:success_message] = permitted[:success_message].presence if permitted.key?(:success_message)
    permitted[:notify_webhook_url] = permitted[:notify_webhook_url].presence if permitted.key?(:notify_webhook_url)
    permitted[:fields] = FormFields.from_params(params.dig(:form, :fields))
    permitted[:webhook_body] = FormWebhookBody.from_params(params.dig(:form, :webhook_body)) if params[:form].key?(:webhook_body)
    permitted
  end

  def apply_template(form, key)
    template = Form::TEMPLATES.find { |t| t[:key] == key.to_s } or return

    form.slug = template[:defaults][:slug] if form.slug.blank?
    form.title = template[:defaults][:title] if form.title.blank?
    form.submit_label = template[:defaults][:submit_label] if template[:defaults][:submit_label] && form.submit_label.in?([nil, "", "Submit"])
    form.success_message = template[:defaults][:success_message] if template[:defaults][:success_message]
    form.fields = template[:fields].deep_dup
  end
end
