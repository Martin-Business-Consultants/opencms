# frozen_string_literal: true

# Site export — the "take my data with me" path, over the API so it can be
# scripted or run before a risky bulk edit.
#
#   GET  /api/tools/backup           — what a backup would contain
#   POST /api/tools/backup           — streams a .tar.gz of DB + blobs
#
# Restoration stays a manual ops procedure; there is deliberately no import
# counterpart here.
class Api::Tools::BackupsController < Api::BaseController
  enforce_authorization
  requires_capability "tools:use", only: [:show, :create]

  def show
  end

  def create
    backup = SiteBackup.new
    send_data backup.export, filename: backup.filename, type: "application/gzip", disposition: "attachment"
  end
end
