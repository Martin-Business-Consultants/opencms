# frozen_string_literal: true

class AddDefaultsAndDeprecatedToBlockTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :block_types, :defaults,   :json,    null: false, default: {}
    add_column :block_types, :deprecated, :boolean, null: false, default: false
  end
end
