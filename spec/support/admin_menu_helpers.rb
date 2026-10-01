# frozen_string_literal: true

# Reading the admin menu (layouts/shared/_admin_menu) out of a response.
module AdminMenuHelpers
  # The top-level items' labels, in order.
  def menu_labels(body = response.body)
    menu = body[%r{<nav id="admin-menu".*?</nav>}m].to_s
    menu.scan(%r{<a [^>]*class="admin-menu__link"[^>]*>.*?<span class="admin-menu__label">([^<]+)</span>}m).flatten
  end

  # The groups, in order, as their items name them.
  def menu_groups(body = response.body)
    body[%r{<nav id="admin-menu".*?</nav>}m].to_s.scan(/data-menu-group="([^"]*)"/).flatten.uniq
  end

  # One top-level item's submenu labels, in order.
  def submenu_labels(label, body = response.body)
    list = body[%r{<ul class="admin-menu__submenu" aria-label="#{Regexp.escape(label)}">.*?</ul>}m].to_s
    list.scan(%r{class="admin-menu__submenu-link"[^>]*>(.*?)</a>}m).flatten.map { it.gsub(/<[^>]+>/, "").squish }
  end
end

RSpec.configure do |config|
  config.include AdminMenuHelpers, type: :request
end
