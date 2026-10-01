# frozen_string_literal: true

# Editorial metadata for the asset library:
#   * `alt` is the accessibility text — required for any image surfaced
#     on the public site, but stored at the asset level so it's reusable.
#   * `focal_x` / `focal_y` are 0..1 floats describing where the visually
#     important part of an image is, used for art-directed crops in the
#     site renderer.
class AddFocalAndAltToAssets < ActiveRecord::Migration[8.0]
  def change
    add_column :assets, :alt,     :string
    add_column :assets, :focal_x, :float, default: 0.5, null: false
    add_column :assets, :focal_y, :float, default: 0.5, null: false
  end
end
