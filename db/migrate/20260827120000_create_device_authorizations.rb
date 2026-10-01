# frozen_string_literal: true

# A pending "connect this machine" handshake, OAuth-device-flow style.
#
# Pasting a token into a config file works and is how this CLI has always been
# set up, but it means the secret is on a clipboard, in a shell history, and
# often in a chat log. The device flow keeps it off all three: the CLI shows a
# short code, the person approves it in the browser they are already signed in
# to, and the token crosses the wire once, to the machine that asked.
class CreateDeviceAuthorizations < ActiveRecord::Migration[8.1]
  def change
    create_table :device_authorizations do |t|
      t.string :user_code, null: false
      t.string :device_code, null: false
      t.references :user, foreign_key: true
      t.datetime :approved_at
      t.datetime :denied_at
      t.datetime :expires_at, null: false
      t.string :hostname

      t.timestamps
    end

    add_index :device_authorizations, :user_code, unique: true
    add_index :device_authorizations, :device_code, unique: true
  end
end
