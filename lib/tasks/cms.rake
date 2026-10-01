# frozen_string_literal: true

namespace :cms do
  # No :environment — it runs before the app (or a new release of it) boots,
  # from bin/update and bin/docker-entrypoint.
  desc "Back up the data directory (CMS_DATA_DIR) to backups/cms-data-<time>.tar.gz, keeping the newest CMS_BACKUP_KEEP (5)"
  task :backup do
    require_relative "../cms/data_backup"

    backup = Cms::DataBackup.for_install
    puts backup.call || "Nothing to back up yet (no databases in #{backup.data_dir})."
  end

  # The container's boot backup: only when this release will migrate, so a
  # plain restart takes none. bin/update and a manual cms:backup always back up.
  desc "Back up the data directory if the database has migrations to run (bin/docker-entrypoint)"
  task :backup_if_pending do
    require_relative "../cms/data_backup"

    backup = Cms::DataBackup.for_install
    archive = backup.call_if_pending(migrations_dirs: Cms::DataBackup.migrations_dirs, env: ENV["RAILS_ENV"].to_s.strip.empty? ? "production" : ENV["RAILS_ENV"])
    puts archive || "No migrations to run: no backup taken."
  end

  desc "Set up this install: starter content, roles, an owner and the machine tokens (JSON on stdout). Idempotent."
  task :bootstrap, [:email, :name] => :environment do |_, args|
    result = SiteSetup.new(owner_email: args[:email] || ENV["CMS_OWNER_EMAIL"], name: args[:name] || ENV["CMS_SITE_NAME"],
      owner_name: ENV["CMS_OWNER_NAME"]).call
    puts JSON.pretty_generate(result.to_h)
  end

  desc "Move one site from the old shared deployment into this install. PATH holds main.sqlite3, " \
       "optionally global.sqlite3 and files/ (the tenant's storage). DRY_RUN=1 to look first, FORCE=1 to replace " \
       "a database that has users; TENANT, SITE_KEY and FILES override what's detected. docs/install.md"
  task :import_tenant, [:path] => :environment do |_, args|
    abort "Usage: bin/rails \"cms:import_tenant[PATH]\"" if args[:path].blank?

    TenantImport.new(args[:path], tenant: ENV["TENANT"], site_key: ENV["SITE_KEY"], files_dir: ENV["FILES"],
      dry_run: ENV["DRY_RUN"].present?, force: ENV["FORCE"].present?).call
  rescue TenantImport::Error => e
    abort e.message
  end

  desc "Reset a user's password (default: the first admin) and print the new one"
  task :reset_admin_password, [:email] => :environment do |_, args|
    user =
      if args[:email].present?
        User.find_by(email: args[:email].to_s.strip.downcase)
      else
        User.joins(:role).where(roles: {system: true}).order(:id).first
      end
    abort "No matching user. Users: #{User.pluck(:email).join(", ")}" unless user

    password = SecureRandom.urlsafe_base64(18)
    # `verified: true` so the new password works at once — an unverified
    # account can be bounced into email confirmation.
    user.update!(password: password, password_confirmation: password, verified: true)

    warn "Reset password for #{user.email}"
    puts password
  end
end
