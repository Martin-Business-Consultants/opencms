# frozen_string_literal: true

class AddSeoToPages < ActiveRecord::Migration[8.0]
  def change
    add_column :pages, :seo, :json, null: false, default: {}
  end
end
