# frozen_string_literal: true

# A `TranslationGroup` collects records that are translations of one
# another — one row per English page, the same row referenced by its
# Spanish/French/etc. siblings via `translation_group_id`. This lets the
# sitemap emit hreflang alternates and the editor jump between locales.
class AddTranslationGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :translation_groups do |t|
      t.string :kind, null: false   # "page" | "collection_entry"
      t.timestamps
    end

    add_reference :pages,             :translation_group, foreign_key: true
    add_reference :collection_entries, :translation_group, foreign_key: true
  end
end
