# frozen_string_literal: true

# Two-factor authentication: a TOTP secret per user, an enable flag (so we
# don't lock the user out before verification), and a list of one-time
# recovery codes (stored hashed). Recovery codes are consumed on use.
class AddTwoFactorToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :totp_secret,            :string
    add_column :users, :totp_enabled,           :boolean, null: false, default: false
    add_column :users, :totp_enabled_at,        :datetime
    add_column :users, :recovery_code_digests,  :json,    null: false, default: []
  end
end
