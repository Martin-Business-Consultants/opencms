# frozen_string_literal: true

# Collapses API tokens from "many scoped, expiring, mint-once tokens per
# user" down to "exactly one token per user, readable forever".
#
# The token is now stored (encrypted, see `ApiToken#token`) alongside the
# digest, so a user can come back weeks later and copy it again instead of
# minting a replacement. Scopes go away entirely — a token carries whatever
# its owner's role carries, checked live on every request, so demoting a
# user still bounds their token.
#
# Data handling, in two passes:
#
#   1. Drop every revoked or expired token. Revocation and expiry are going
#      away as concepts, so leaving those rows behind would quietly bring a
#      deliberately-killed credential back to life.
#   2. Of what's left, keep each user's *live* token — most recently used,
#      then most recently created — so a provisioned site that's actively
#      pulling content keeps working.
#
# Surviving rows have no stored plaintext (it never existed), so the UI
# shows them as "rotate to reveal" until their owner rotates. A user whose
# every token was revoked ends up with none and gets a fresh one minted on
# their next visit to Settings → API token.
class PersonalizeApiTokens < ActiveRecord::Migration[8.0]
  def up
    add_column :api_tokens, :token, :text, if_not_exists: true

    if column_exists?(:api_tokens, :revoked_at)
      execute("DELETE FROM api_tokens WHERE revoked_at IS NOT NULL")
    end

    if column_exists?(:api_tokens, :expires_at)
      execute(<<~SQL.squish)
        DELETE FROM api_tokens
        WHERE expires_at IS NOT NULL AND expires_at <= #{connection.quote(Time.current)}
      SQL
    end

    # Keep one row per user. ROW_NUMBER over a preference ordering beats a
    # MAX(id) group-by here: the newest token is often *not* the one in use.
    execute <<~SQL
      DELETE FROM api_tokens
      WHERE id NOT IN (
        SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY user_id
                   ORDER BY (last_used_at IS NOT NULL) DESC,
                            last_used_at DESC,
                            created_at DESC,
                            id DESC
                 ) AS rn
          FROM api_tokens
        )
        WHERE rn = 1
      )
    SQL

    remove_index :api_tokens, column: [:user_id, :revoked_at], if_exists: true
    remove_index :api_tokens, column: :user_id, if_exists: true
    add_index :api_tokens, :user_id, unique: true

    remove_column :api_tokens, :name,       if_exists: true
    remove_column :api_tokens, :scopes,     if_exists: true
    remove_column :api_tokens, :expires_at, if_exists: true
    remove_column :api_tokens, :revoked_at, if_exists: true
  end

  def down
    add_column :api_tokens, :name,       :string,   if_not_exists: true
    add_column :api_tokens, :scopes,     :json,     if_not_exists: true, null: false, default: []
    add_column :api_tokens, :expires_at, :datetime, if_not_exists: true
    add_column :api_tokens, :revoked_at, :datetime, if_not_exists: true

    execute("UPDATE api_tokens SET name = 'API token' WHERE name IS NULL")
    change_column_null :api_tokens, :name, false

    remove_index :api_tokens, column: :user_id, if_exists: true
    add_index :api_tokens, :user_id
    add_index :api_tokens, [:user_id, :revoked_at]

    remove_column :api_tokens, :token, if_exists: true
  end
end
