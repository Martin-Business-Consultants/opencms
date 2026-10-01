# frozen_string_literal: true

require "digest"
require "fileutils"
require "sqlite3"

# Moves one site from the old multi-tenant deployment into this install
# (bin/rails "cms:import_tenant[PATH]", docs/install.md).
#
# The old deployment kept a SQLite database per tenant
# (storage/production/<tenant>/main.sqlite3) and Active Storage blobs keyed
# `<tenant>/<token>`, with each file at storage/<tenant>/<to>/<ke>/<token>.
# PATH is a directory holding:
#
#   main.sqlite3 (+ -wal, -shm)   the tenant's database, required
#   global.sqlite3                the old global database, optional (owner email, site name)
#   files/                        the tenant's storage/<tenant>/ directory, optional
#                                 (also found as PATH/<tenant>/ or PATH/storage/<tenant>/)
#
# The import:
#
#   1. copies the database and checkpoints the copy (the source is never
#      opened for writing);
#   2. checks the install is empty (no users), unless force;
#   3. puts the copy in place of this install's database (the one it replaces
#      is kept beside it) and runs the migrations it's behind on;
#   4. strips the `<tenant>/` prefix from blob keys and copies each file to
#      this install's storage, checking its checksum;
#   5. gives the old tenant's owner the Admin role;
#   6. reads every encrypted column, and reports the ones this install's keys
#      can't decrypt (the old deployment's keys have to be this install's).
#
# dry_run stops after 2 and says what would happen. Re-running with force
# starts again from the source, so it's idempotent.
class TenantImport
  class Error < StandardError; end

  Blob = Data.define(:id, :key, :token, :checksum, :source, :state)

  attr_reader :source_dir, :tenant, :site_key, :warnings

  def initialize(source_dir, tenant: nil, site_key: nil, files_dir: nil, dry_run: false, force: false, out: $stdout)
    @source_dir = Pathname(source_dir.to_s).expand_path
    @source_db = @source_dir.join("main.sqlite3")
    @global_db = %w[global.sqlite3 production_global.sqlite3].map { @source_dir.join(it) }.find(&:file?)
    @tenant_option = tenant.presence
    @site_key_option = site_key.presence
    @files_option = files_dir.presence
    @dry_run = dry_run
    @force = force
    @out = out
    @warnings = []
  end

  def call
    raise Error, "No main.sqlite3 in #{@source_dir}" unless @source_db.file?
    raise Error, "#{@source_db} is this install's own database" if same_file?(@source_db, target_db)

    @work_dir = Rails.root.join("tmp/tenant_import", Time.current.strftime("%Y%m%d%H%M%S%L"))
    copy_source
    @tenant = (@tenant_option || tenant_from_blobs || tenant_from_global || @source_dir.basename.to_s).to_s
    @site_key = (@site_key_option || @tenant).to_s
    @files_dir = Pathname((@files_option || [@source_dir.join("files"), @source_dir.join(@tenant), @source_dir.join("storage", @tenant)].find(&:directory?)).to_s)

    plan = inspect_copy
    report_plan(plan)

    if !@force && target_has_users?
      raise Error, "This install already has users — importing would replace its database. Re-run with FORCE=1 to replace it (the current database is kept beside it)."
    end

    return finish(dry_run: true) if @dry_run

    kept = replace_database
    applied = migrate
    blobs = move_blobs
    owner = carry_owner
    undecryptable = check_encryption

    report_import(kept:, applied:, blobs:, owner:, undecryptable:)
    finish
  ensure
    FileUtils.rm_rf(@work_dir) if @work_dir
  end

  private

  # ── 1. The copy ────────────────────────────────────────────────────────

  # Both databases are copied, WAL files and all, and only the copies are
  # ever opened: SQLite removes a database's -wal and -shm files when its
  # last connection closes, read-only or not, so opening the source itself
  # would change PATH.
  def copy_source
    FileUtils.mkdir_p(@work_dir)
    copy_database(@source_db, copy_db)
    copy_database(@global_db, copy_global_db) if @global_db
  end

  def copy_database(source, copy)
    ["", "-wal", "-shm"].each do |suffix|
      file = Pathname("#{source}#{suffix}")
      FileUtils.cp(file, "#{copy}#{suffix}") if file.file?
    end

    db = SQLite3::Database.new(copy.to_s)
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    db.execute("PRAGMA journal_mode=DELETE")
    db.close
    ["-wal", "-shm"].each { FileUtils.rm_f("#{copy}#{it}") }
  end

  def copy_db = @work_dir.join("main.sqlite3")

  def copy_global_db = @work_dir.join("global.sqlite3")

  def read_copy(&) = read_sqlite(copy_db, &)

  # The block's result (SQLite3::Database.new with a block returns the
  # database, not what the block did).
  def read_sqlite(path)
    db = SQLite3::Database.new(path.to_s, readonly: true, results_as_hash: true)
    yield db
  ensure
    db&.close
  end

  def tenant_from_blobs
    read_copy do |db|
      next unless table?(db, "active_storage_blobs")

      db.execute("SELECT key FROM active_storage_blobs WHERE key LIKE '%/%' LIMIT 1").first&.dig("key")&.split("/", 2)&.first
    end
  end

  def tenant_from_global
    tenants = global_tenants
    tenants.first&.dig("subdomain") if tenants.one?
  end

  def global_tenants
    return [] unless @global_db

    read_sqlite(copy_global_db) do |db|
      table?(db, "tenants") ? db.execute("SELECT subdomain, name, owner_email FROM tenants") : []
    end
  end

  def old_tenant
    @old_tenant ||= global_tenants.find { it["subdomain"] == tenant }
  end

  # ── 2. What's in it ────────────────────────────────────────────────────

  def inspect_copy
    read_copy do |db|
      tables = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").map { it["name"] }
      counts = (tables - %w[schema_migrations ar_internal_metadata]).to_h { [it, db.execute(%(SELECT COUNT(*) AS n FROM "#{it}")).first["n"]] }
      versions = tables.include?("schema_migrations") ? db.execute("SELECT version FROM schema_migrations").map { it["version"] } : []
      {counts:, versions:, blobs: tables.include?("active_storage_blobs") ? planned_blobs(db) : []}
    end
  end

  def planned_blobs(db)
    db.execute("SELECT id, key, checksum FROM active_storage_blobs ORDER BY id").map do |row|
      key = row["key"]
      prefixed = key.start_with?("#{tenant}/")
      token = prefixed ? key.delete_prefix("#{tenant}/") : key
      source = @files_dir.to_s.present? ? @files_dir.join(token[0, 2], token[2, 2], token) : nil
      state =
        if source.nil? || !source.file? then :missing
        elsif row["checksum"].present? && Digest::MD5.file(source).base64digest != row["checksum"] then :checksum_mismatch
        else :ok
        end
      Blob.new(id: row["id"], key:, token:, checksum: row["checksum"], source:, state:)
    end
  end

  def pending_versions(versions)
    migration_context.migrations.map { it.version.to_s } - versions.map(&:to_s)
  end

  def migration_context
    pool = ActiveRecord::Base.connection_pool
    ActiveRecord::MigrationContext.new(ActiveRecord::Tasks::DatabaseTasks.migrations_paths, pool.schema_migration, pool.internal_metadata)
  end

  def target_has_users?
    File.exist?(target_db) && ActiveRecord::Base.connection.table_exists?("users") && User.exists?
  end

  # ── 3. The database ────────────────────────────────────────────────────

  def target_db
    Pathname(ActiveRecord::Base.connection_db_config.database).expand_path(Rails.root)
  end

  # The install's database (and its WAL) moves aside; the copy takes its place.
  def replace_database
    ActiveRecord::Base.connection_pool.disconnect!
    kept = nil
    if target_db.file?
      kept = Pathname("#{target_db}.before-import-#{Time.current.strftime("%Y%m%d%H%M%S")}")
      FileUtils.mv(target_db, kept)
    end
    %w[-wal -shm].each { FileUtils.rm_f("#{target_db}#{it}") }
    FileUtils.mkdir_p(target_db.dirname)
    FileUtils.cp(copy_db, target_db)
    kept
  end

  def migrate
    context = migration_context
    pending = context.migrations.count { !context.get_all_versions.include?(it.version) }
    context.migrate
    ActiveRecord::Base.connection_pool.internal_metadata[:environment] = ActiveRecord::Base.connection_db_config.env_name
    ActiveRecord::Base.descendants.reject(&:abstract_class?).each(&:reset_column_information)
    pending
  end

  # ── 4. Files ───────────────────────────────────────────────────────────

  def move_blobs
    service = ActiveStorage::Blob.service
    unless service.respond_to?(:path_for)
      raise Error, "This install's Active Storage service (#{service.class}) isn't the Disk service; move the files by hand."
    end

    tally = Hash.new(0)
    ActiveStorage::Blob.find_each do |blob|
      token = blob.key.delete_prefix("#{tenant}/")
      source = @files_dir.to_s.present? ? @files_dir.join(token[0, 2], token[2, 2], token) : nil
      destination = Pathname(service.path_for(token))

      if source&.file?
        FileUtils.mkdir_p(destination.dirname)
        FileUtils.cp(source, destination)
      end

      state =
        if !destination.file? then :missing
        elsif blob.checksum.present? && Digest::MD5.file(destination).base64digest != blob.checksum then :checksum_mismatch
        else :copied
        end
      @warnings << "blob ##{blob.id} (#{blob.filename}): #{state.to_s.tr("_", " ")}" unless state == :copied

      blob.update_columns(key: token, service_name: service.name.to_s)
      tally[state] += 1
    end
    tally
  end

  # ── 5. The owner ───────────────────────────────────────────────────────

  def carry_owner
    email = old_tenant&.dig("owner_email")
    user = email && User.find_by(email: email.to_s.strip.downcase)

    if email.nil?
      @warnings << "no owner found (no global database, or no tenant #{tenant.inspect} in it)"
      nil
    elsif user.nil?
      @warnings << "the owner #{email} isn't a user in the imported database"
      nil
    else
      admin = Role.find_by(name: "Admin", system: true)
      user.update_columns(role_id: admin.id) if admin && user.role_id != admin.id
      email
    end
  end

  # ── 6. Encryption ──────────────────────────────────────────────────────

  def check_encryption
    Rails.application.eager_load!
    encrypted = ActiveRecord::Base.descendants.reject(&:abstract_class?).select { it.encrypted_attributes.present? && it.table_exists? }

    encrypted.each_with_object({}) do |model, failures|
      model.unscoped.find_each do |record|
        model.encrypted_attributes.each do |attribute|
          record.public_send(attribute)
        rescue ActiveRecord::Encryption::Errors::Decryption
          failures["#{model.name}##{attribute}"] = failures.fetch("#{model.name}##{attribute}", 0) + 1
        end
      end
    end
  end

  # ── Reporting ──────────────────────────────────────────────────────────

  def report_plan(plan)
    pending = pending_versions(plan[:versions])
    unknown = plan[:versions].map(&:to_s) - migration_context.migrations.map { it.version.to_s }
    blob_states = plan[:blobs].group_by(&:state).transform_values(&:size)

    @out.puts "Importing tenant #{tenant.inspect} from #{@source_dir}#{" (dry run)" if @dry_run}"
    @out.puts "  owner: #{old_tenant ? "#{old_tenant["owner_email"]} (#{old_tenant["name"]})" : "unknown"}"
    @out.puts "  records: " + plan[:counts].select { |_, n| n.positive? }.map { |table, n| "#{table} #{n}" }.join(", ")
    @out.puts "  migrations to run: #{pending.size}"
    @out.puts "  blobs: #{plan[:blobs].size} (#{blob_states.map { |state, n| "#{n} #{state.to_s.tr("_", " ")}" }.join(", ").presence || "none"})"
    @out.puts "  files from: #{@files_dir.to_s.presence || "(no files directory found)"}"
    @warnings << "the source has #{unknown.size} migration(s) this install doesn't know: #{unknown.first(5).join(", ")}" if unknown.any?
    plan[:blobs].reject { it.state == :ok }.each { @warnings << "blob ##{it.id} (#{it.key}): #{it.state.to_s.tr("_", " ")} in the source" }
  end

  def report_import(kept:, applied:, blobs:, owner:, undecryptable:)
    @out.puts "Imported into #{target_db}#{" (the previous database is at #{kept})" if kept}"
    @out.puts "  migrations run: #{applied}"
    @out.puts "  blobs: #{blobs.map { |state, n| "#{n} #{state.to_s.tr("_", " ")}" }.join(", ").presence || "none"}"
    @out.puts "  owner: #{owner || "not set"}"
    @out.puts "  records: " + counts_now.map { |table, n| "#{table} #{n}" }.join(", ")
    if undecryptable.any?
      @warnings << "encrypted values this install can't read (#{undecryptable.map { |column, n| "#{column} × #{n}" }.join(", ")}): " \
                   "give it the old deployment's SECRET_KEY_BASE and no AR_ENCRYPTION_* of its own, or re-enter them"
    end
  end

  def counts_now
    connection = ActiveRecord::Base.connection
    (connection.tables - %w[schema_migrations ar_internal_metadata]).sort.filter_map do |table|
      n = connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)}").to_i
      [table, n] if n.positive?
    end
  end

  def finish(dry_run: false)
    @warnings.each { @out.puts "  ! #{it}" }
    @out.puts <<~NEXT.chomp
      #{dry_run ? "Nothing was changed." : "Done."} Set, for this install:
        APP_HOST=#{site_key}.librepublish.com
        SITE_KEY=#{site_key}
      and drain the old deployment's job queue before switching the hostname over.
    NEXT
    self
  end

  def table?(db, name)
    db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [name]).any?
  end

  def same_file?(a, b)
    File.exist?(a) && File.exist?(b) && File.identical?(a, b)
  end
end
