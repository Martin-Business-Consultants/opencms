# frozen_string_literal: true

# What a device login is for: "user" (the CLI acting as the person who
# approves it, as before) or "site" (a site's installer asking for a
# read-only service token of its own), and what that site calls itself.
class AddPurposeToDeviceAuthorizations < ActiveRecord::Migration[8.1]
  def change
    add_column :device_authorizations, :purpose, :string, default: "user", null: false
    add_column :device_authorizations, :label, :string
  end
end
