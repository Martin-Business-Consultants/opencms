# frozen_string_literal: true

require "rubygems/package"
require "zlib"
require "json"

# Bundles the site's data into a tar.gz the editor can download.
# The bundle contains:
#
#   manifest.json    — site key, generated_at, file inventory
#   db/main.sqlite3  — the primary database file
#   blobs/<key>      — every Active Storage blob referenced from this DB
#                      (looked up via Asset rows)
#
# Restoration is left as a manual / ops process for now. The intent is "I
# can leave this provider and take my data with me," not "one-click
# import into a fresh instance."
class SiteBackup
  # Raised rather than silently shipping a bundle with no database in it.
  # An empty backup that reports success is worse than a failed one.
  MissingDatabase = Class.new(StandardError)

  # What a backup would hold, by kind: the core's content and what enabled
  # plugins count (`counts … backup: true`), in reading order.
  def self.contents
    core = {
      pages:       Page.count,
      collections: Collection.count,
      entries:     CollectionEntry.count,
      block_types: BlockType.count,
      globals:     Global.count,
      assets:      Asset.count
    }
    additions = Cms::Plugins.enabled_counters.select(&:backup).map { |counter| [counter.name, counter.count.call, counter.after] }
    Cms::Plugins.arrange(core.to_a, additions).to_h
  end

  # The archives bin/update and the container's boot left in the data
  # directory (Cms::DataBackup), newest first.
  def self.data_archives
    Cms::DataBackup.for_install.archives
  end

  # The whole bundle as a string, for a download, recorded as an export.
  def export
    buffer = StringIO.new
    bytes = dump_to(buffer)
    Event.record("site_backup.exported", bytes: bytes)
    buffer.string
  end

  # Streams the tar.gz bundle into the given IO. Returns the byte count
  # written so the controller can log it.
  def dump_to(io)
    bytes_before = io.respond_to?(:size) ? io.size : 0

    Zlib::GzipWriter.wrap(io) do |gz|
      Gem::Package::TarWriter.new(gz) do |tar|
        write_manifest(tar)
        write_db(tar)
        write_blobs(tar)
      end
    end

    io.respond_to?(:size) ? (io.size - bytes_before) : 0
  end

  def filename
    "cms-backup-#{Site.key}-#{Time.current.strftime("%Y%m%d-%H%M%S")}.tar.gz"
  end

  private

  def write_manifest(tar)
    payload = {
      tenant:       Site.key,
      generated_at: Time.current.iso8601,
      includes:     {db: db_path.present? && File.exist?(db_path), blobs: blob_keys.size}
    }
    write_file(tar, "manifest.json", JSON.pretty_generate(payload))
  end

  def write_db(tar)
    path = db_path
    raise MissingDatabase, "no database file at #{path.inspect}" unless path.present? && File.exist?(path)

    checkpoint_wal!
    write_file(tar, "db/main.sqlite3", File.binread(path))
  end

  # SQLite runs in WAL mode, so recent commits can still be sitting in
  # `main.sqlite3-wal` rather than the database file we're about to read.
  # Folding the log back in first is the difference between a backup that
  # contains today's edits and one that quietly doesn't.
  def checkpoint_wal!
    ApplicationRecord.connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
  rescue StandardError => e
    # A failed checkpoint costs us the newest writes, not the backup. Log
    # loudly and carry on rather than denying the user their data.
    Rails.logger.warn("[SiteBackup] WAL checkpoint failed: #{e.class}: #{e.message}")
  end

  def write_blobs(tar)
    blob_keys.each do |key|
      path = blob_path_for(key)
      next unless path && File.exist?(path)

      write_file(tar, "blobs/#{key}", File.binread(path))
    end
  end

  def blob_keys
    @blob_keys ||= ActiveStorage::Attachment
      .where(record_type: "Asset", record_id: Asset.with_discarded.pluck(:id))
      .joins(:blob)
      .pluck("active_storage_blobs.key")
      .uniq
  end

  def db_path
    @db_path ||= ApplicationRecord.connection_db_config.database.to_s
  end

  # Where the Disk service keeps a blob. Asked of the service rather than
  # rebuilt here: rebuilding it by hand is how blobs used to go missing from
  # backups without an error.
  def blob_path_for(key)
    service = ActiveStorage::Blob.service
    service.path_for(key) if service.respond_to?(:path_for)
  end

  def write_file(tar, path, body)
    tar.add_file_simple(path, 0o644, body.bytesize) { |io| io.write(body) }
  end
end
