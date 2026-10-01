# frozen_string_literal: true

# A collection's icon in the admin menu and on its screens: a lucide name, as
# the templates carry it (Collection::Iconic maps it onto the admin's icons).
# Collections made from a template before this get that template's icon.
class AddIconToCollections < ActiveRecord::Migration[8.1]
  TEMPLATE_ICONS = {
    "posts" => "FileText", "news" => "Newspaper", "team" => "Users", "products" => "Package",
    "events" => "Calendar", "faqs" => "HelpCircle", "testimonials" => "Quote",
    "case-studies" => "BarChart3", "press" => "Megaphone", "recipes" => "ChefHat",
    "jobs" => "Briefcase", "projects" => "LayoutGrid", "locations" => "MapPin"
  }.freeze

  def up
    add_column :collections, :icon, :string

    TEMPLATE_ICONS.each do |slug, icon|
      execute "UPDATE collections SET icon = #{connection.quote(icon)} WHERE slug = #{connection.quote(slug)} AND icon IS NULL"
    end
  end

  def down
    remove_column :collections, :icon
  end
end
