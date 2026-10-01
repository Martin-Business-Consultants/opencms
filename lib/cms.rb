# frozen_string_literal: true

# The core's name and version. The VERSION file is the one place the version
# is written: bin/update prints it, Settings shows it, /version serves it, and
# a plugin's `requires:` is checked against it.
module Cms
  VERSION = Rails.root.join("VERSION").read.strip.freeze

  def self.version = Gem::Version.new(VERSION)

  # Where this install keeps its databases and uploads (CMS_DATA_DIR, as
  # config/database.yml and config/storage.yml read it), so whatever else it
  # writes there is backed up with them.
  def self.data_dir = Pathname(ENV["CMS_DATA_DIR"].presence || Rails.root.join("storage"))
end
