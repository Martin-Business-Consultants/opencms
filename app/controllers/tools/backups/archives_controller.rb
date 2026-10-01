# frozen_string_literal: true

# Downloads one of the data-directory archives Tools › Backup lists. The file
# is looked up among the archives that exist, never built from the URL.
class Tools::Backups::ArchivesController < ApplicationController
  requires_capability "tools:use", only: :show

  def show
    archive = SiteBackup.data_archives.find { it.name == params[:name] } or raise ActiveRecord::RecordNotFound

    Event.record("data_backup.downloaded", archive: archive.name, bytes: archive.byte_size)
    send_file archive.path, filename: archive.name, type: "application/gzip", disposition: "attachment"
  end
end
