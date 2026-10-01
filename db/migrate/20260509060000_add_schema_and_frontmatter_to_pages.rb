# frozen_string_literal: true

class AddSchemaAndFrontmatterToPages < ActiveRecord::Migration[8.0]
  def change
    add_column :pages, :schema,      :json, null: false, default: {"fields" => []}
    add_column :pages, :frontmatter, :json, null: false, default: {}
  end
end
