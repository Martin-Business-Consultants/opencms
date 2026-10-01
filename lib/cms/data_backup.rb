# frozen_string_literal: true

require "fileutils"
require "sqlite3"
require "tmpdir"
require "time"

module Cms
  # A copy of an install's whole data directory (CMS_DATA_DIR: every SQLite
  # database and every uploaded file) as one .tar.gz, taken before bin/update
  # or a container boot migrates anything. Databases are copied with SQLite's
  # online backup API, so a copy taken while the app is running is consistent
  # (WAL included); everything else is copied as files.
  #
  # Plain Ruby — no Rails — so bin/update and bin/docker-entrypoint can run it
  # before the new code boots.
  #
  #   Cms::DataBackup.new(data_dir: "/var/lib/cms").call  # => "/var/lib/cms/backups/cms-data-20260927-120000.tar.gz"
  class DataBackup
    DEFAULT_KEEP = 5
    SQLITE_SIDECARS = /-(wal|shm|journal)\z/

    attr_reader :data_dir, :backup_dir, :keep

    def initialize(data_dir:, backup_dir: nil, keep: nil)
      @data_dir   = File.expand_path(data_dir)
      @backup_dir = File.expand_path(backup_dir || File.join(@data_dir, "backups"))
      @keep       = (keep || DEFAULT_KEEP).to_i
    end

    # The archive's path, or nil when there is nothing to back up yet (a fresh
    # install). Raises when a copy fails: an update must not go ahead without
    # its backup.
    def call
      return nil unless databases.any?

      FileUtils.mkdir_p(backup_dir)
      archive = File.join(backup_dir, "cms-data-#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}.tar.gz")

      Dir.mktmpdir("cms-backup") do |staging|
        copy_into(staging)
        system("tar", "-czf", archive, "-C", staging, ".", exception: true)
      end

      prune!
      archive
    end

    # A backup only when this boot will migrate: the primary database lacks a
    # migration the code has. A plain restart takes none. Returns the archive,
    # or nil (fresh install, or nothing pending).
    def call_if_pending(migrations_dirs:, env: "production")
      pending_migrations?(migrations_dirs:, env:) ? call : nil
    end

    # Whether the primary database (`<env>.sqlite3` in data_dir) is missing any
    # of the migrations in `migrations_dirs`. False for a fresh install, which
    # has no database to protect.
    def pending_migrations?(migrations_dirs:, env: "production")
      primary = File.join(data_dir, "#{env}.sqlite3")
      return false unless File.file?(primary)

      expected = Array(migrations_dirs).flat_map { Dir.glob(File.join(it, "*.rb")) }
        .filter_map { File.basename(it)[/\A(\d{14})_/, 1] }
      (expected - applied_versions(primary)).any?
    end

    # This install's, from the environment bin/update and cms:backup read.
    def self.for_install(env = ENV)
      value = ->(name) { env[name].to_s.strip.empty? ? nil : env[name] }
      new(data_dir: value.("CMS_DATA_DIR") || File.expand_path("../../storage", __dir__),
        backup_dir: value.("CMS_BACKUP_DIR"), keep: value.("CMS_BACKUP_KEEP"))
    end

    Archive = Struct.new(:name, :path, :byte_size, :taken_at, keyword_init: true)

    ARCHIVE_NAME = /\Acms-data-(\d{8})-(\d{6})\.tar\.gz\z/

    # The archives in backup_dir, newest first.
    def archives
      Dir.glob(File.join(backup_dir, "cms-data-*.tar.gz")).filter_map do |path|
        name = File.basename(path)
        match = name.match(ARCHIVE_NAME) or next
        Archive.new(name: name, path: path, byte_size: File.size(path),
          taken_at: Time.strptime("#{match[1]}#{match[2]} UTC", "%Y%m%d%H%M%S %Z"))
      end.sort_by(&:name).reverse
    end

    def databases
      Dir.glob(File.join(data_dir, "*.sqlite3"))
    end

    # The app's own migrations and its engines', as bin/rails would find them.
    def self.migrations_dirs(root = File.expand_path("../..", __dir__))
      [File.join(root, "db/migrate"), *Dir.glob(File.join(root, "engines/*/db/migrate"))]
    end

    private

    def applied_versions(primary)
      db = SQLite3::Database.new(primary, readonly: true)
      db.execute("SELECT version FROM schema_migrations").flatten.map(&:to_s)
    rescue SQLite3::Exception
      []
    ensure
      db&.close
    end

    def copy_into(staging)
      Dir.children(data_dir).each do |entry|
        source = File.join(data_dir, entry)
        next if File.expand_path(source) == backup_dir || entry.match?(SQLITE_SIDECARS)

        if entry.end_with?(".sqlite3")
          backup_database(source, File.join(staging, entry))
        else
          FileUtils.cp_r(source, staging, preserve: true)
        end
      end
    end

    def backup_database(source, destination)
      from = SQLite3::Database.new(source, readonly: true)
      to = SQLite3::Database.new(destination)
      backup = SQLite3::Backup.new(to, "main", from, "main")
      backup.step(-1)
      backup.finish
    ensure
      to&.close
      from&.close
    end

    # Keep the newest `keep` archives.
    def prune!
      archives = Dir.glob(File.join(backup_dir, "cms-data-*.tar.gz")).sort
      (archives - archives.last(keep)).each { |old| File.delete(old) }
    end
  end
end
