# frozen_string_literal: true

# "Restore this version": the version's blocks go back through the editor's
# own save, so a live page edited by someone who can't publish becomes a
# revision for review, as any other edit would.
class Pages::Versions::RestorationsController < ApplicationController
  requires_capability "pages:write", only: :create

  include PageScoped
  include ContentEditing

  def create
    version = @page.versions.find(params[:version_id])
    prior_status = @page.status
    outcome = save_content(@page, version.snapshot, prefix: "pages")

    if outcome == :invalid
      redirect_to page_version_path(@page.path, version), alert: @page.errors.full_messages.to_sentence
    else
      @page.track_update(from: prior_status) if outcome == :saved
      after_content_save(outcome, edit_page_path(@page.path), saved: "Version restored")
    end
  end
end
