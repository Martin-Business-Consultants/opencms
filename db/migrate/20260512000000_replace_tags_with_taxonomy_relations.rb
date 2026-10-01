# frozen_string_literal: true

# Replace the flat `tags` JSON arrays on pages + collection_entries with
# proper relations:
#
#   * Each Page / CollectionEntry has one optional `category_entry_id`
#     (FK → collection_entries).
#   * Each Page / CollectionEntry has many `tags` through `taggings`
#     (polymorphic taggable_type/taggable_id; tag_entry_id → collection_entries).
#   * Each Collection points at the Collection that holds its category /
#     tag pools (`categories_collection_id`, `tags_collection_id`), so the
#     admin picker knows which entries to show. Pages use the convention
#     slugs `page-categories` and `page-tags`.
class ReplaceTagsWithTaxonomyRelations < ActiveRecord::Migration[8.0]
  def change
    # Pool wiring on Collection — self-referential FKs, nullable so a
    # collection can opt out of either taxonomy.
    add_reference :collections, :categories_collection,
                  foreign_key: {to_table: :collections}, null: true
    add_reference :collections, :tags_collection,
                  foreign_key: {to_table: :collections}, null: true

    # Category is single per record. Self-referential on collection_entries
    # because a category IS just an entry in another collection.
    add_reference :pages, :category_entry,
                  foreign_key: {to_table: :collection_entries}, null: true
    add_reference :collection_entries, :category_entry,
                  foreign_key: {to_table: :collection_entries}, null: true

    # Polymorphic tag join. tag_entry_id always points at a CollectionEntry
    # in the configured tags-pool collection.
    create_table :taggings do |t|
      t.string  :taggable_type, null: false
      t.integer :taggable_id,   null: false
      t.references :tag_entry, null: false,
                                foreign_key: {to_table: :collection_entries, on_delete: :cascade}
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :taggings, [:taggable_type, :taggable_id], name: "index_taggings_on_taggable"
    add_index :taggings, [:taggable_type, :taggable_id, :tag_entry_id],
              unique: true, name: "index_taggings_uniq"

    # Drop the flat JSON tag arrays — relation now owns this concern.
    remove_column :pages, :tags, :json, null: false, default: []
    remove_column :collection_entries, :tags, :json, null: false, default: []
  end
end
