# frozen_string_literal: true

class Api::FormsController < Api::BaseController
  include PluginGated
  plugin :forms

  enforce_authorization
  requires_capability "forms:read",   only: [:index, :show]
  requires_capability "forms:write",  only: [:create, :update]
  requires_capability "forms:delete", only: [:destroy]

  before_action :find_form, only: [:show, :update, :destroy]

  def index
    @forms = Form.ordered
    @forms = @forms.where(status: params[:status]) if params[:status].present?
  end

  def show
  end

  def create
    @form = Form.new(form_params)
    @form.save!
    @form.track_event(:created, slug: @form.slug)
    render :show, status: :created
  end

  def update
    @form.update!(form_params)
    @form.track_event(:updated, slug: @form.slug)
    render :show
  end

  def destroy
    @form.track_event(:deleted, slug: @form.slug)
    @form.destroy!
    head :no_content
  end

  private

  def find_form
    @form = Form.find_by!(slug: params[:slug])
  end


  # `permit(fields: [...])` deep-permits the field hash array including its
  # nested `options` repeater for select/radio types.
  def form_params
    params.require(:form).permit(
      :slug, :title, :status, :submit_url, :submit_label, :success_message,
      :notify_emails, :notify_webhook_url,
      fields: [
        :name, :label, :type, :required, :placeholder, :help, :default,
        :accept, :multiple, :max_size,
        {options: [:value, :label]}
      ]
    )
  end
end
