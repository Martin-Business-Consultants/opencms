# frozen_string_literal: true

# "Restore this version": the version's fields, body and blocks go back
# through the editor's own save, so a live entry edited by someone who can't
# publish becomes a revision for review, as any other edit would.
class Collections::Entries::Versions::RestorationsController < ApplicationController
  requires_capability "entries:write", only: :create

  include EntryScoped
  include ContentEditing

  def create
    version = @entry.versions.find(params[:version_id])
    prior_status = @entry.status
    outcome = save_content(@entry, version.snapshot, prefix: "entries")

    if outcome == :invalid
      redirect_to collection_entry_version_path(@collection.slug, @entry.slug, version), alert: @entry.errors.full_messages.to_sentence
    else
      @entry.track_update(from: prior_status) if outcome == :saved
      after_content_save(outcome, edit_collection_entry_path(@collection.slug, @entry.slug), saved: "Version restored")
    end
  end
end
