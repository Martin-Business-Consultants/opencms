# frozen_string_literal: true

class CreateCmsCore < ActiveRecord::Migration[8.0]
  def change
    create_table :pages do |t|
      t.string   :slug,         null: false
      t.string   :title,        null: false
      t.string   :status,       null: false, default: "draft"
      t.string   :locale,       null: false, default: "en"
      t.json     :tags,         null: false, default: []
      t.json     :blocks,       null: false, default: []
      t.datetime :published_at
      t.timestamps

      t.index :slug, unique: true
      t.index :status
      t.index :locale
      t.index :published_at
    end

    create_table :page_versions do |t|
      t.references :page,   null: false, foreign_key: true
      t.references :author, foreign_key: {to_table: :users}
      t.json     :blocks,  null: false, default: []
      t.string   :comment
      t.datetime :created_at, null: false

      t.index [:page_id, :created_at]
    end

    create_table :collections do |t|
      t.string :slug,   null: false
      t.string :name,   null: false
      t.json   :schema, null: false, default: {}
      t.timestamps

      t.index :slug, unique: true
    end

    create_table :collection_entries do |t|
      t.references :collection, null: false, foreign_key: true
      t.string   :slug,           null: false
      t.string   :title,          null: false
      t.string   :status,         null: false, default: "draft"
      t.string   :locale,         null: false, default: "en"
      t.json     :tags,           null: false, default: []
      t.json     :frontmatter,    null: false, default: {}
      t.text     :body_markdown,  null: false, default: ""
      t.datetime :published_at
      t.timestamps

      t.index [:collection_id, :slug], unique: true
      t.index :status
      t.index :published_at
    end

    create_table :collection_entry_versions do |t|
      t.references :collection_entry, null: false, foreign_key: true
      t.references :author, foreign_key: {to_table: :users}
      t.json     :frontmatter,   null: false, default: {}
      t.text     :body_markdown, null: false, default: ""
      t.string   :comment
      t.datetime :created_at, null: false

      t.index [:collection_entry_id, :created_at]
    end

    create_table :content_references do |t|
      t.references :owner, polymorphic: true, null: false
      t.string   :ref_type, null: false
      t.string   :ref_id,   null: false
      t.string   :kind,     null: false
      t.integer  :position
      t.datetime :created_at, null: false

      t.index [:ref_type, :ref_id]
      t.index [:owner_type, :owner_id, :kind]
    end

    # FTS5 virtual tables. Kept in sync from Ruby (after_save in Page /
    # CollectionEntry) so we can extract block text via the block registry
    # rather than fight SQL triggers over JSON.
    create_virtual_table :pages_fts, :fts5, [
      "slug UNINDEXED",
      "title",
      "body",
      "tokenize = 'porter'"
    ]

    create_virtual_table :collection_entries_fts, :fts5, [
      "slug UNINDEXED",
      "collection_slug UNINDEXED",
      "title",
      "body",
      "tokenize = 'porter'"
    ]
  end
end
