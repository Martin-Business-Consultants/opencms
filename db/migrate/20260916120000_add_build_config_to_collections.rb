# frozen_string_literal: true

# The Build board: an optional two-column view over a collection's entries,
# where the column a card sits in IS one boolean frontmatter field. Drag a
# special into "On the menu" and `active` becomes true — no form, no save.
#
# Which field drives the columns (and which fields stay editable on the card)
# is per-collection configuration, so it lives beside the collection rather
# than inside `schema`. `schema` is replaced wholesale by every schema PATCH —
# admin form and `cms schema collection …` alike — so a key parked in there
# would quietly evaporate the next time somebody edited the field list.
class AddBuildConfigToCollections < ActiveRecord::Migration[8.1]
  def change
    add_column :collections, :build_config, :json, default: {}, null: false
  end
end
