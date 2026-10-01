# frozen_string_literal: true

# The admin menu down the left of every admin page, in the manner of
# WordPress's: top-level items with an icon, in groups, each with a submenu,
# and the admin bar's "+ New" menu. Enabled plugins add top-level items,
# submenu links and "+ New" entries through Cms::Plugins (menu, submenu,
# new_item). Every link shows only when the role grants its capability.
module NavigationHelper
  # A top-level item: its id (what plugins' submenus and `after:` name), label,
  # icon, where it goes, the capability it needs, and its submenu of
  # [label, path, capability]. A path is a route helper's name, or a lambda
  # run in the view (nil hides the link). An item without a path goes to the
  # first submenu link the role may see.
  ADMIN_MENU = {
    nil => [
      {id: :dashboard, label: "Dashboard", icon: "home", path: :dashboard_path}
    ],
    "Content" => [
      {id: :pages, label: "Pages", icon: "document", path: :pages_path, capability: "pages:read", submenu: [
        ["All pages", :pages_path, "pages:read"],
        ["Add new", :new_page_path, "pages:write"],
        ["Sitemap", :sitemap_path, "pages:read"]
      ]},
      {id: :collections, label: "Collections", icon: "stack", path: :collections_path, capability: "collections:read",
       submenu: [
         ["All collections", :collections_path, "collections:read"],
         ["Add new", :new_collection_path, "collections:write"]
       ]},
      {id: :globals, label: "Globals", icon: "world", path: :globals_path, capability: "globals:read", submenu: [
        ["All globals", :globals_path, "globals:read"],
        ["Add new", :new_global_path, "globals:write"]
      ]},
      {id: :media, label: "Media", icon: "image", path: :file_manager_path, capability: "assets:read", submenu: [
        ["Library", :file_manager_path, "assets:read"]
      ]}
    ],
    "Structure" => [
      {id: :block_types, label: "Block types", icon: "grid", path: :block_types_path, capability: "block_types:read",
       submenu: [
         ["All block types", :block_types_path, "block_types:read"],
         ["Add new", :new_block_type_path, "block_types:write"]
       ]},
      # How a frontend (the Astro site) works with this headless CMS.
      {id: :developers, label: "Developers", icon: "code", path: :developers_path, capability: "pages:read"}
    ],
    # Plugins' home (Agents); shown only when one puts something in it.
    "Automation" => [],
    "Insights" => [
      {id: :approvals, label: "Approvals", icon: "check-circle", path: :approvals_path, capability: "pages:read",
       submenu: [
         ["Approvals", :approvals_path, "pages:read"],
         ["Reviews", :review_requests_path, "pages:read"],
         ["Pending changes", :revisions_path, "pages:read"],
         ["Findings", :recommendations_path, "recommendations:read"]
       ]},
      {id: :audit_log, label: "Audit log", icon: "history", path: :audit_logs_path, capability: "audit_log:read"},
      {id: :trash, label: "Trash", icon: "trash", path: :trash_path, capability: "trash:read"}
    ],
    "Tools" => [
      {id: :tools, label: "Tools", icon: "wrench", submenu: [
        ["Redirects", :tools_redirects_path, "redirects:read"],
        ["Schedules", :tools_recurring_tasks_path, "tools:use"],
        ["Webhooks", :webhooks_path, "webhooks:read"],
        ["Backup", :tools_backup_path, "tools:use"]
      ]}
    ],
    "Access" => [
      {id: :users, label: "Users", icon: "everyone", path: :users_path, capability: "users:read", submenu: [
        ["All users", :users_path, "users:read"],
        ["Add new", :new_user_path, "users:write"]
      ]},
      {id: :roles, label: "Roles", icon: "lock", path: :roles_path, capability: "roles:read", submenu: [
        ["All roles", :roles_path, "roles:read"],
        ["Add new", :new_role_path, "roles:write"]
      ]}
    ],
    "Help" => [
      {id: :docs, label: "Docs", icon: "help-circle", path: :docs_path, capability: "pages:read", submenu: [
        ["All docs", :docs_path, "pages:read"],
        ["Working with Astro", -> { doc_path("astro") }, "pages:read"],
        ["Working with AI", -> { doc_path("ai") }, "pages:read"],
        ["Before going live", :go_live_docs_path, "pages:read"],
        ["Site health", :site_health_docs_path, "pages:read"]
      ]}
    ],
    "Settings" => [
      {id: :settings, label: "Settings", icon: "settings-outline", path: :settings_path}
    ]
  }.freeze

  # The admin bar's "+ New" menu: [label, path, capability].
  NEW_ITEMS = [
    ["Page", :new_page_path, "pages:write"],
    ["Collection", :new_collection_path, "collections:write"],
    ["Global", :new_global_path, "globals:write"],
    ["Media", -> { file_manager_path(upload: 1) }, "assets:write"],
    ["Block type", :new_block_type_path, "block_types:write"],
    ["User", :new_user_path, "users:write"]
  ].freeze

  # The collections listed by name under Collections, at most this many.
  COLLECTIONS_IN_MENU = 12

  MenuEntry = Struct.new(:id, :label, :icon, :url, :current, :submenu, keyword_init: true)
  SubmenuEntry = Struct.new(:label, :url, :current, :icon, keyword_init: true)

  # [[group, [MenuEntry, …]], …] for the admin menu, with empty items and
  # groups left out and the current item (the one whose links best match this
  # page) marked, along with its current submenu link.
  def admin_menu
    @admin_menu ||= mark_current(menu_groups)
  end

  # [[label, url], …] for "+ New": the core's, each collection's "Entry in …",
  # then enabled plugins' (Cms::Plugins.new_item).
  def admin_new_items
    core = NEW_ITEMS.filter_map do |label, path, capability|
      [label, resolve_path(path)] if permitted?(capability)
    end
    if permitted?("entries:write")
      menu_collections.each { |collection| core << ["Entry in #{collection.name}", new_collection_entry_path(collection.slug)] }
    end
    additions = Cms::Plugins.enabled_new_items.filter_map do |item|
      next unless permitted?(item.capability)

      url = instance_exec(&item.path)
      [item.label, url, item.after] if url
    end
    Cms::Plugins.arrange(core, additions)
  end

  # A link marked as the current page anywhere in its section (/pages, /pages/9…).
  # keys: the go-to chord for the keyboard controller ("g p"), shown in the title.
  def nav_link_to(label, path, keys: nil, **options)
    current = path_matches?(path)
    options = options.merge(title: "#{label} (#{keys})", data: (options[:data] || {}).merge(keys: keys)) if keys
    link_to label, path, **options, aria: {current: ("page" if current)}
  end

  # The page one level up. Not a button: a <link rel="up"> in the head, which
  # Esc follows (keyboard_controller).
  def parent_page(label, url)
    content_for :parent_page, tag.link(rel: "up", href: url_for(url), title: label)
    nil
  end

  # Where "View site" goes: Settings › General's site address, if set.
  def public_site_url
    Setting.get("general")["site_base_url"].presence
  rescue StandardError
    nil
  end

  private

  def menu_groups
    groups = ADMIN_MENU.to_h { |group, items| [group, items.map { core_menu_item(it) }] }
    add_plugin_items(groups)
    add_plugin_submenus(groups)

    groups.filter_map do |group, items|
      entries = items.filter_map { |item| menu_entry(item) }
      [group, entries] if entries.any?
    end
  end

  def core_menu_item(item)
    submenu = Array(item[:submenu]).map { |label, path, capability| {label: label, path: path, capability: capability} }
    submenu += collection_submenu if item[:id] == :collections
    submenu = settings_submenu if item[:id] == :settings
    item.merge(submenu: submenu)
  end

  def collection_submenu
    return [] unless permitted?("entries:read")

    menu_collections.map do |collection|
      {label: collection.name, icon: collection.admin_icon, path: -> { collection_entries_path(collection.slug) }}
    end
  end

  def settings_submenu
    [{label: "All settings", path: :settings_path}] +
      settings_sections.flat_map { |_, links| links.map { |label, url, _| {label: label, path: -> { url }} } }
  end

  def menu_collections
    @menu_collections ||= Collection.order(:name).limit(COLLECTIONS_IN_MENU).to_a
  rescue ActiveRecord::StatementInvalid
    []
  end

  # Plugins' top-level items join their group (after the item `after`
  # names), or start a group of their own after `group_after`, before
  # Settings when that's not given.
  def add_plugin_items(groups)
    Cms::Plugins.enabled_menu_items.group_by(&:group).each do |group, items|
      unless groups.key?(group)
        anchor = items.filter_map(&:group_after).first
        placed = Cms::Plugins.arrange(groups.except("Settings").to_a, [[group, [], anchor]]) + [["Settings", groups["Settings"]]]
        groups.replace(placed.to_h)
      end

      core = groups[group].map { |item| [item[:id], item] }
      additions = items.map do |item|
        [item.id, {id: item.id, label: item.label, icon: item.icon, path: item.path, capability: item.capability, submenu: []}, item.after]
      end
      groups[group] = Cms::Plugins.arrange(core, additions).map(&:last)
    end
  end

  def add_plugin_submenus(groups)
    items = groups.values.flatten.index_by { it[:id] }
    Cms::Plugins.enabled_submenu_items.group_by(&:parent).each do |parent, links|
      item = items[parent] or next
      core = item[:submenu].map { |link| [link[:label], link] }
      additions = links.map { |link| [link.label, {label: link.label, path: link.path, capability: link.capability}, link.after] }
      item[:submenu] = Cms::Plugins.arrange(core, additions).map(&:last)
    end
  end

  def menu_entry(item)
    return unless permitted?(item[:capability])

    submenu = item[:submenu].filter_map do |link|
      next unless permitted?(link[:capability])

      url = resolve_path(link[:path])
      SubmenuEntry.new(label: link[:label], url: url, current: false, icon: link[:icon]) if url
    end
    url = item[:path] ? resolve_path(item[:path]) : submenu.first&.url
    return unless url

    MenuEntry.new(id: item[:id], label: item[:label], icon: item[:icon], url: url, current: false, submenu: submenu)
  end

  # The item whose own link or submenu links match this page most closely is
  # current, and within it the closest submenu link.
  def mark_current(groups)
    best = groups.flat_map(&:last).max_by { |entry| match_length(entry) }
    if best && match_length(best).positive?
      best.current = true
      closest = best.submenu.max_by { |link| path_match_length(link.url) }
      closest.current = true if closest && path_match_length(closest.url).positive?
    end
    groups
  end

  def match_length(entry)
    ([entry.url] + entry.submenu.map(&:url)).map { path_match_length(it) }.max
  end

  # How much of this request's path the link covers: its length when the
  # request is the link's page or below it, else 0.
  def path_match_length(url)
    path = URI.parse(url.to_s).path.to_s.chomp("/")
    return 0 if path.empty?

    (request.path == path || request.path.start_with?("#{path}/")) ? path.length : 0
  rescue URI::InvalidURIError
    0
  end

  def path_matches?(url) = path_match_length(url).positive? || request.path == url

  def resolve_path(path)
    path.is_a?(Proc) ? instance_exec(&path) : public_send(path)
  end

  def permitted?(capability) = capability.nil? || Current.user&.can?(capability)
end
