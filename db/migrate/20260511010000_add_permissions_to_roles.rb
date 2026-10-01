# frozen_string_literal: true

class AddPermissionsToRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :roles, :permissions, :json,    null: false, default: []
    add_column :roles, :system,      :boolean, null: false, default: false
  end
end
