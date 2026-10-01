# frozen_string_literal: true

# Third-party tags the public site loads — analytics, pixels, chat widgets.
#
# A row is a labelled snippet with a consent category. The category is the
# point: the consent banner decides per category, and a script only reaches
# the visitor's browser once its category has been granted. Storing tags
# here rather than pasting them into the site's layout is what makes that
# decision enforceable.
class CreateScripts < ActiveRecord::Migration[8.1]
  def change
    create_table :scripts do |t|
      # What a person calls it ("GA4", "Chat widget") and who made it.
      t.string :name,   null: false
      t.string :vendor

      # necessary | functional | analytics | marketing — see Script::CATEGORIES.
      t.string :category,  null: false, default: "analytics"
      # head | body_start | body_end
      t.string :placement, null: false, default: "head"

      # An external file, an inline snippet, or both (the gtag pattern is a
      # loader file followed by a config call). At least one is required.
      t.string  :src
      t.text    :code
      t.boolean :async, null: false, default: true
      t.boolean :defer, null: false, default: false

      t.boolean :active, null: false, default: true
      t.text    :notes

      t.timestamps

      t.index [:category, :active]
    end
  end
end
