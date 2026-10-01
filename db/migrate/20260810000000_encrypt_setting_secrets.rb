# frozen_string_literal: true

# Settings are a generic key/value store with a plain JSON `data` column, and
# the AI provider API key has been living in it in cleartext. Anyone with read
# access to the tenant database — a backup, a copied file, an over-broad query —
# could read it.
#
# Secrets move to their own column so the rest of `data` stays queryable and
# untouched. It is text rather than json because Active Record encryption
# produces a ciphertext string; the model layers JSON serialization on top.
#
# Schema only. Moving existing cleartext keys across needs the model (to write
# them encrypted) and has to run once per tenant database, which a migration
# body can't do from an untenanted connection — see
# `bin/rails settings:encrypt_api_keys`, which is the second half of this change.
class EncryptSettingSecrets < ActiveRecord::Migration[8.0]
  def up
    add_column :settings, :secrets, :text, if_not_exists: true
  end

  def down
    remove_column :settings, :secrets, if_exists: true
  end
end
