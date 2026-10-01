# frozen_string_literal: true

require "rails_helper"

# An old tenant is built here from scratch: a database in the old layout (one
# migration behind, blob keys prefixed `acme/`), its files under
# files/<xx>/<yy>/<token>, and a global database naming its owner. The import
# runs into a throwaway database, never the test one.
RSpec.describe TenantImport do
  self.use_transactional_tests = false

  let(:dir) { Pathname(Dir.mktmpdir("tenant-import")) }
  let(:source) { dir.join("acme").tap(&:mkpath) }
  let(:target) { dir.join("install.sqlite3") }
  let(:out) { StringIO.new }
  let(:token) { "abcdtoken1234567890" }
  let(:contents) { "the mill in 1890" }

  before { build_old_tenant }

  after do
    FileUtils.rm_f(ActiveStorage::Blob.service.path_for(token))
    FileUtils.rm_rf(dir)
  end

  def on_database(path)
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: path.to_s)
    ActiveRecord::Base.descendants.each(&:reset_column_information)
    yield
  ensure
    ActiveRecord::Base.establish_connection(:test)
    ActiveRecord::Base.descendants.each(&:reset_column_information)
  end

  def build_old_tenant
    on_database(source.join("main.sqlite3")) do
      ActiveRecord::Schema.verbose = false
      load Rails.root.join("db/schema.rb")
      ActiveRecord::Base.connection.remove_column :revisions, :agent_run_id
      pool = ActiveRecord::Base.connection_pool
      versions = ActiveRecord::MigrationContext.new(ActiveRecord::Tasks::DatabaseTasks.migrations_paths, pool.schema_migration, pool.internal_metadata).migrations.map(&:version)
      pool.schema_migration.delete_all_versions
      (versions - [20260928130000]).each { pool.schema_migration.create_version(it) }
      ActiveRecord::Base.descendants.each(&:reset_column_information)

      Role.system_admin
      owner = create(:user, email: "owner@acme.test", admin: false)
      create(:user, email: "editor@acme.test", admin: false)
      foreign = ActiveRecord::Encryption::Encryptor.new.encrypt("mbc_old", key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("the old deployment's key"))
      # Written raw: update_columns would encrypt it again with this install's key.
      ActiveRecord::Base.connection.execute(ApiToken.sanitize_sql(["UPDATE api_tokens SET token = ? WHERE user_id = ?", foreign, owner.id]))

      ActiveStorage::Blob.insert_all!([
        {key: "acme/#{token}", filename: "mill.txt", content_type: "text/plain", byte_size: contents.bytesize,
         checksum: Digest::MD5.base64digest(contents), service_name: "local", metadata: "{}", created_at: Time.current},
        {key: "acme/gonetoken000000", filename: "lost.txt", content_type: "text/plain", byte_size: 1,
         checksum: Digest::MD5.base64digest("x"), service_name: "local", metadata: "{}", created_at: Time.current}
      ])
    end

    source.join("files", token[0, 2], token[2, 2]).tap(&:mkpath).join(token).write(contents)

    SQLite3::Database.new(source.join("global.sqlite3").to_s) do |db|
      db.execute("CREATE TABLE tenants (subdomain TEXT, name TEXT, owner_email TEXT)")
      db.execute("INSERT INTO tenants VALUES ('acme', 'Acme Mill', 'Owner@acme.test')")
    end
  end

  def import(**options)
    on_database(target) do
      result = described_class.new(source, out:, **options).call
      yield if block_given?
      result
    end
  end

  it "moves the database, the files and the owner over, and says what to set" do
    import = import do
      expect(User.pluck(:email)).to contain_exactly("owner@acme.test", "editor@acme.test")
      expect(User.find_by(email: "owner@acme.test").role).to eq(Role.system_admin)
      expect(ActiveRecord::Base.connection.column_exists?(:revisions, :agent_run_id)).to be(true)
      expect(ActiveRecord::Base.connection_pool.internal_metadata[:environment]).to eq("test")

      blob = ActiveStorage::Blob.find_by(filename: "mill.txt")
      expect(blob).to have_attributes(key: token, service_name: "test")
      expect(blob.download).to eq(contents)
      expect(ActiveStorage::Blob.pluck(:key)).to all(satisfy { !it.include?("/") })
    end

    expect(import.tenant).to eq("acme")
    expect(out.string).to include("migrations run: 1", "blobs: 1 copied, 1 missing", "owner: Owner@acme.test",
      "APP_HOST=acme.librepublish.com", "SITE_KEY=acme")
    expect(import.warnings).to include(a_string_matching(/lost\.txt\): missing/), a_string_matching(/ApiToken#token × 1/))
  end

  it "refuses an install that already has users unless forced, and a forced re-run lands the same" do
    import
    counts = on_database(target) { [User.count, ActiveStorage::Blob.pluck(:key).sort] }

    expect { import }.to raise_error(described_class::Error, /already has users/)

    import(force: true) do
      expect([User.count, ActiveStorage::Blob.pluck(:key).sort]).to eq(counts)
      expect(ActiveStorage::Blob.find_by(key: token).download).to eq(contents)
    end
    expect(dir.glob("install.sqlite3.before-import-*")).to be_present
  end

  it "changes nothing on a dry run" do
    import(dry_run: true)

    expect(on_database(target) { ActiveRecord::Base.connection.tables }).to be_empty
    expect(File).not_to exist(ActiveStorage::Blob.service.path_for(token))
    expect(out.string).to include("(dry run)", "migrations to run: 1", "blobs: 2 (1 ok, 1 missing)", "Nothing was changed.")
  end

  # SQLite deletes a database's -wal and -shm when its last connection
  # closes, even a read-only one, so an import that opened PATH's own files
  # would change them. The WAL here holds a change not yet in the main file.
  it "leaves PATH exactly as it was, WAL files included, and reads what the WAL holds" do
    elsewhere = dir.join("elsewhere").tap(&:mkpath)
    FileUtils.cp(source.join("global.sqlite3"), elsewhere)
    held = SQLite3::Database.new(elsewhere.join("global.sqlite3").to_s)
    held.execute("PRAGMA journal_mode=WAL")
    held.execute("PRAGMA wal_autocheckpoint=0")
    held.execute("UPDATE tenants SET owner_email = 'wal-owner@acme.test'")
    %w[global.sqlite3 global.sqlite3-wal global.sqlite3-shm].each { FileUtils.cp(elsewhere.join(it), source.join(it)) }
    held.close

    listing = -> { source.children.select(&:file?).to_h { [it.basename.to_s, [it.size, it.mtime, Digest::SHA256.file(it).hexdigest]] } }
    before = listing.call
    expect(before.keys).to include("global.sqlite3-wal", "global.sqlite3-shm")

    import

    expect(listing.call).to eq(before)
    expect(out.string).to include("owner: wal-owner@acme.test")
  end

  it "says what's missing" do
    expect { described_class.new(dir.join("nowhere"), out:).call }.to raise_error(described_class::Error, /No main.sqlite3/)
  end
end
