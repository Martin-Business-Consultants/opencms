# frozen_string_literal: true

# Tools › Backup. A privileged user downloads a portable copy of the site's
# data (database and uploaded files) as one tar.gz (SiteBackup), and sees the
# archives of the whole data directory that bin/update and the container's
# boot keep (Cms::DataBackup). Restoring stays an ops procedure (docs/install.md).
class Tools::BackupsController < ApplicationController
  requires_capability "tools:use", only: [:show, :create]

  def show
    @contents = SiteBackup.contents
    @archives = SiteBackup.data_archives
  end

  def create
    backup = SiteBackup.new
    send_data backup.export, filename: backup.filename, type: "application/gzip", disposition: "attachment"
  end
end
