# frozen_string_literal: true

# Credentials for machines rather than people.
#
# Until now the only token was `ApiToken`, one per user, carrying that user's
# role. A published site therefore ran on a person's credential — in practice
# the tenant owner's, which is an admin — so the secret in the site's
# environment could write, delete and publish, and any ordinary act on that
# account (rotating the token, a role change, a migration that collapses
# tokens) took the site down with it.
#
# A service token belongs to the tenant instead: it has a name, its own role,
# and no person behind it. Many per tenant, revocable one at a time.
class CreateServiceTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :service_tokens do |t|
      t.string   :name,         null: false
      t.text     :description
      t.references :role,       null: false
      t.references :created_by, null: true
      t.text     :token                       # encrypted plaintext, so it can be shown again
      t.string   :token_digest, null: false   # what authentication looks up
      t.string   :prefix,       null: false
      t.datetime :last_used_at
      t.string   :last_used_ip
      t.datetime :revoked_at
      t.timestamps

      t.index :token_digest, unique: true
      t.index :revoked_at
    end
  end
end
