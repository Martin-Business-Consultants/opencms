# frozen_string_literal: true

# Persistent API tokens with scopes, expiry, and revocation. Replaces the
# stateless `User#signed_id(purpose: :api)` flow so we can:
#   * grant a subset of the user's permissions per token
#   * record when a token was last used
#   * revoke a leaked token without rotating the user's password
#
# Plaintext is shown once at issue time. The DB stores only the SHA-256
# digest, plus a short prefix for display + lookup.
class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name,         null: false
      t.string  :prefix,       null: false  # first 12 chars (mbc_xxxxxxxx) for display
      t.string  :token_digest, null: false  # sha256(plaintext) — unique
      t.json    :scopes,       null: false, default: []
      t.datetime :expires_at
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.string :last_used_ip
      t.timestamps

      t.index :token_digest, unique: true
      t.index :prefix
      t.index [:user_id, :revoked_at]
    end
  end
end
