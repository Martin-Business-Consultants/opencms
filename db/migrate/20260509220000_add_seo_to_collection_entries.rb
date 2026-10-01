# frozen_string_literal: true

class AddSeoToCollectionEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :collection_entries, :seo, :json, null: false, default: {}
  end
end
