# frozen_string_literal: true

# Forms: the list's Active switch. On publishes the form (it takes
# submissions); off takes it back to a draft.
class Forms::ActivationsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "forms:write", only: :update

  def update
    form = Form.find_by!(slug: params[:form_slug])
    form.update!(status: params[:active] == "1" ? "published" : "draft")
    form.track_event(:updated, slug: form.slug)
    redirect_to forms_path, notice: form.status == "published" ? "“#{form.title}” is active" : "“#{form.title}” is inactive"
  end
end
