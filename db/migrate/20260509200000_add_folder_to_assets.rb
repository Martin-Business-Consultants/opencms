# frozen_string_literal: true

class AddFolderToAssets < ActiveRecord::Migration[8.0]
  def change
    add_column :assets, :folder, :string, null: false, default: "/"
    add_index  :assets, :folder
  end
end
