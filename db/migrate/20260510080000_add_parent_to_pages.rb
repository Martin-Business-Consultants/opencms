# frozen_string_literal: true

# Pages become a tree via adjacency list (`parent_id`) plus a denormalized
# `path` column kept in sync by a model callback. `path` is what URLs and
# lookups go through; `slug` reverts to a per-parent leaf segment.
class AddParentToPages < ActiveRecord::Migration[8.0]
  def up
    add_reference :pages, :parent, foreign_key: {to_table: :pages}, null: true
    add_column    :pages, :path,  :string
    add_column    :pages, :depth, :integer, default: 0, null: false

    # Existing pages are flat (no parent), so path = slug, depth = 0.
    execute "UPDATE pages SET path = slug, depth = 0"
    change_column_null :pages, :path, false

    remove_index :pages, :slug
    add_index    :pages, :path,                unique: true
    add_index    :pages, [:parent_id, :slug],  unique: true
  end

  def down
    remove_index :pages, [:parent_id, :slug]
    remove_index :pages, :path
    add_index    :pages, :slug, unique: true

    remove_column :pages, :depth
    remove_column :pages, :path
    remove_reference :pages, :parent, foreign_key: {to_table: :pages}
  end
end
