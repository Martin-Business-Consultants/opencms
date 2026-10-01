# frozen_string_literal: true

# One status for every ticked entry (CollectionEntry.change_status_of).
class Collections::Entries::BulkStatusChangesController < ApplicationController
  include CollectionScoped

  requires_capability "entries:publish", only: :create

  def create
    status = params[:status].to_s
    slugs = Array(params[:slugs]).map(&:to_s).reject(&:empty?)

    if CollectionEntry::STATUSES.exclude?(status)
      redirect_to collection_entries_path(@collection.slug), alert: "Pick a status to set."
    else
      entries = CollectionEntry.change_status_of(@collection.entries.where(slug: slugs).to_a, to: status, collection: @collection)
      redirect_to collection_entries_path(@collection.slug), notice: "#{entries.size} #{"entry".pluralize(entries.size)} set to #{status}"
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to collection_entries_path(@collection.slug), alert: "#{e.record.slug}: #{e.record.errors.full_messages.to_sentence}"
  end
end
