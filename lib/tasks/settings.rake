# frozen_string_literal: true

# Second half of the EncryptSettingSecrets migration.
#
# The migration adds the column; this moves any cleartext API key out of the
# plain `data` JSON and into the encrypted `secrets` column, then removes it
# from `data`. Leaving the original behind would defeat the point, so the scrub
# is not optional.
#
# It lives here rather than in the migration because it needs the model to
# write the value encrypted.
#
#   bin/rails settings:encrypt_api_keys
#
# Idempotent: a settings row whose key already moved is skipped.
namespace :settings do
  desc "Move cleartext Setting API keys into the encrypted secrets column"
  task encrypt_api_keys: :environment do
    moved = 0
    skipped = 0

    Setting.find_each do |setting|
      data = setting.read_attribute(:data) || {}
      key = data["api_key"]

      if key.blank?
        skipped += 1
        next
      end

      setting.set_secrets(api_key: key)
      setting.update_columns(data: data.except("api_key"))
      moved += 1
      puts "  #{setting.key}: moved api_key into encrypted storage"
    end

    puts moved.zero? ? "No cleartext API keys found (#{skipped} settings row(s) checked)." :
                       "Encrypted #{moved} API key(s)."
  end
end
