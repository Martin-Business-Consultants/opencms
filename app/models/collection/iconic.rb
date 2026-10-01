# frozen_string_literal: true

# A collection's icon: a lucide name (what the templates carry, and what the
# API and the Astro site would recognise), drawn with the admin's own icon
# set. Names the set has no match for draw as the stack.
module Collection::Iconic
  extend ActiveSupport::Concern

  ADMIN_ICONS = {
    "FileText" => "document", "Newspaper" => "newspaper", "Users" => "everyone",
    "Package" => "package", "Calendar" => "calendar", "HelpCircle" => "help-circle",
    "Quote" => "quote", "BarChart3" => "chart", "Megaphone" => "megaphone",
    "ChefHat" => "chef-hat", "Briefcase" => "briefcase", "LayoutGrid" => "grid",
    "MapPin" => "marker", "Image" => "image", "Tag" => "tag", "Globe" => "globe",
    "Link" => "link", "Star" => "bookmark", "Home" => "home", "Mail" => "email"
  }.freeze

  DEFAULT_ADMIN_ICON = "stack"

  # For a select: each lucide name the admin can draw, labelled.
  def self.options
    ADMIN_ICONS.keys.map { [it.underscore.humanize, it] }
  end

  def admin_icon
    ADMIN_ICONS.fetch(icon.to_s, DEFAULT_ADMIN_ICON)
  end
end
