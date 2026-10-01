# frozen_string_literal: true

# Forms: the list's Duplicate, a draft copy to edit (Form#duplicate!).
class Forms::DuplicationsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "forms:write", only: :create

  def create
    copy = Form.find_by!(slug: params[:form_slug]).duplicate!
    copy.track_event(:created, slug: copy.slug)
    redirect_to edit_form_path(copy.slug), notice: "Form duplicated"
  end
end
