# frozen_string_literal: true

# Forms: moving the ticked forms to the trash in one go.
class Forms::BulkDeletionsController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "forms:delete", only: :create

  def create
    slugs = Array(params[:slugs]).map(&:to_s).reject(&:empty?)
    forms = Form.where(slug: slugs).to_a.each(&:discard!)
    Form.track_event(:bulk_deleted, count: forms.size, slugs: forms.map(&:slug)) if forms.any?
    redirect_to forms_path, notice: "#{forms.size} #{"form".pluralize(forms.size)} moved to trash"
  end
end
