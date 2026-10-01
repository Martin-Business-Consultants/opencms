# frozen_string_literal: true

# An asset's caption (shown with it on the site) and description (a note
# about it), as WordPress's attachments have, beside its name and alt text.
class AddCaptionAndDescriptionToAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :assets, :caption, :text
    add_column :assets, :description, :text
  end
end
