# frozen_string_literal: true

# The core's extension points. A plugin — a Rails engine, bundled in engines/
# or installed into plugins/ — registers itself and what it adds here; the
# core renders what is registered for plugins that are switched on (Settings ›
# Plugins) and never names a plugin. Plugins start off unless their manifest
# says `enabled_by_default: true`. engines/hello is the reference plugin and
# docs/plugins.md the guide.
#
#   Cms::Plugins.register :hello, name: "Hello", version: "0.1.0",
#     description: "…", requires: ">= 1.0", depends_on: [:ai]
#   Cms::Plugins.menu :hello, :hello, label: "Hello", icon: "reaction", group: "Tools",
#     path: -> { hello_greetings_path }, capability: "hello:read"
#   Cms::Plugins.submenu :hello, :tools, label: "Greetings", path: -> { hello_greetings_path }
#   Cms::Plugins.new_item :hello, label: "Greeting", path: -> { new_hello_greeting_path }
#   Cms::Plugins.slot :dashboard, :hello, "hello/slots/dashboard"
#   Cms::Plugins.settings :hello, "Hello", -> { hello_settings_path }, description: "…"
#   Cms::Plugins.permissions :hello, "Hello", %w[hello:read hello:write]
#   Cms::Plugins.stylesheet :hello, "hello/hello"
#   Cms::Plugins.nightly :hello, -> { Hello::TidyJob.perform_later }
#   Cms::Plugins.minutely :hello, :sweep, -> { Hello::SweepJob.perform_later }, every: 5
#   Cms::Plugins.bootstrap :hello, -> { Hello::Starter.seed! }
#   Cms::Plugins.api :hello, "/api/hello/greetings", description: "…"
#
# Where the core lists things in an order someone reads (the admin menu, the role
# editor, Settings, the manifest's counts, the trash's kinds, the schedules,
# the webhook events), `after:` puts a plugin's addition straight after the
# item it names; without it the addition goes last. It may name another
# plugin's item, and may be a list — the first one present wins — so
# `after: ["Forms", "Globals"]` follows Forms when that's on and Globals when
# it isn't, whichever plugin loads first. `after: :start` puts it first.
#
# Registries that only a later plugin will use keep to a register/read API:
# agent tools, report definitions, importer adapters, script presets, block
# type packs, schema field types and deploy providers.
#
# Content events. Every webhook event (Webhook.events: the core's page.published,
# page.updated, page.unpublished, page.deleted, the same for entry and
# global.updated, plus what installed plugins add with
# `webhook_events`) is also published in-process through ActiveSupport::Notifications as
# "<event>.cms" with {event:, data:} (data: the webhook payload), and
# page.created / entry.created the same way plus `record:`. A subscriber
# checks `Cms::Plugins.enabled?(key)` itself:
#
#   ActiveSupport::Notifications.subscribe("page.published.cms") do |event|
#     next unless Cms::Plugins.enabled?(:hello)
#     …event.payload[:data]…
#   end
module Cms
  module Plugins
    Manifest = Struct.new(:key, :name, :version, :description, :author, :bundled, :enabled_by_default,
      :requires, :depends_on, :homepage, :adopt_if, keyword_init: true) do
      # requires: a Gem::Requirement on the core's version (">= 1.1").
      def compatible?
        requires.blank? || Gem::Requirement.new(requires).satisfied_by?(Cms.version)
      end
    end

    SETTING_KEY = "plugins"

    # `after: START` (:start): before everything else in the list.
    START = :start

    SLOT_NAMES = {
      nav_actions: "Admin bar",
      dashboard: "Dashboard panel",
      webhook_filters: "Webhook filters"
    }.freeze

    # The built-in roles a plugin can grant capabilities to by default
    # (`permissions … defaults:`), as Permissions.defaults_for names them.
    DEFAULT_ROLES = %i[editor author site agent].freeze

    # Events published as "<event>.cms" (see above).
    def self.events = Webhook.events + %w[page.created entry.created]

    mattr_reader :manifests, default: {}
    mattr_reader :slots, default: Hash.new { |hash, name| hash[name] = {} }
    mattr_reader :menu_items, default: Hash.new { |hash, key| hash[key] = [] }
    mattr_reader :submenu_items, default: Hash.new { |hash, key| hash[key] = [] }
    mattr_reader :new_items, default: Hash.new { |hash, key| hash[key] = [] }
    mattr_reader :settings_pages, default: {}
    mattr_reader :permission_groups, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :stylesheets, default: Hash.new { |hash, key| hash[key] = [] }
    mattr_reader :nightly_tasks, default: {}
    mattr_reader :minutely_tasks, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :bootstrap_tasks, default: {}
    mattr_reader :api_endpoints, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :agent_tools, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :agent_capabilities, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :report_definitions, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :importers, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :script_presets, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :block_type_packs, default: {}
    mattr_reader :field_types, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :deploy_providers, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :permission_placements, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :permission_defaults, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :counters, default: Hash.new { |hash, key| hash[key] = [] }
    mattr_reader :manifest_sections, default: Hash.new { |hash, key| hash[key] = [] }
    mattr_reader :trash_kinds, default: Hash.new { |hash, key| hash[key] = [] }
    mattr_reader :recurring_recipes, default: Hash.new { |hash, key| hash[key] = [] }
    mattr_reader :providers, default: Hash.new { |hash, key| hash[key] = {} }
    mattr_reader :webhook_event_groups, default: {}
    mattr_reader :webhook_event_filters, default: Hash.new { |hash, key| hash[key] = {} }

    MenuItem = Struct.new(:id, :label, :icon, :path, :capability, :group, :after, :group_after, keyword_init: true)
    SubmenuItem = Struct.new(:parent, :label, :path, :capability, :after, keyword_init: true)
    NewItem = Struct.new(:label, :path, :capability, :after, keyword_init: true)
    WebhookEventGroup = Struct.new(:label, :events, :after, :deploy, keyword_init: true)
    WebhookEventFilter = Struct.new(:permit, :validate, :match, keyword_init: true)
    SettingsPage = Struct.new(:label, :path, :description, :capability, :group, :after, keyword_init: true)
    Counter = Struct.new(:name, :count, :after, :backup, keyword_init: true)
    ManifestSection = Struct.new(:name, :build, :after, keyword_init: true)
    TrashKind = Struct.new(:kind, :model, :label, :meta, :after, keyword_init: true) do
      def klass = model.constantize
    end
    RecurringRecipe = Struct.new(:recipe, :after, keyword_init: true) do
      def klass = recipe.constantize
    end
    BlockTypePack = Struct.new(:block_types, :package, keyword_init: true)
    FieldType = Struct.new(:validator, :partial, keyword_init: true)
    MinutelyTask = Struct.new(:task, :every, keyword_init: true) do
      def due?(at) = (at.to_i / 60) % every == 0
    end

    class << self
      # Everything is keyed by the plugin, so registering again on a code
      # reload replaces rather than duplicates.
      #
      # bundled: ships with the core (engines/). enabled_by_default: starts on.
      # requires: the core versions it works with. depends_on: other plugins'
      # keys that must be on for this one to be.
      #
      # adopt_if: a lambda answering whether this install already uses what
      # the plugin now holds (a core feature moved into a plugin: its tables
      # have rows). While nobody has switched the plugin on or off, a true
      # answer switches it on, so an upgrade never takes a feature away.
      def register(key, name:, version:, description:, author: nil, bundled: false, enabled_by_default: false,
        requires: nil, depends_on: [], homepage: nil, adopt_if: nil)
        key = key.to_sym
        manifests[key] = Manifest.new(key: key, name: name, version: version, description: description, author: author,
          bundled: bundled, enabled_by_default: enabled_by_default, requires: requires,
          depends_on: Array(depends_on).map(&:to_sym), homepage: homepage, adopt_if: adopt_if)
        [menu_items, submenu_items, new_items, stylesheets, counters, manifest_sections, trash_kinds, recurring_recipes].each { it.delete(key) }
        webhook_event_groups.delete(key)
        manifests[key]
      end

      # A partial rendered in a core view's slot (SLOT_NAMES), with that
      # slot's locals.
      def slot(name, key, partial)
        slots[name.to_sym][key.to_sym] = partial
      end

      # A top-level item in the admin menu (WordPress's add_menu_page), with
      # its icon (an icon_tag name), in `group` — a core group ("Content",
      # "Tools", …, NavigationHelper::ADMIN_MENU) or a new one, which sits
      # after `group_after` (else last, before Settings). id: what submenus
      # and `after:` name it by. path: a lambda run in the view; nil hides
      # the item. after: the id of the item it follows in its group.
      def menu(key, id, label:, icon:, path:, group:, capability: nil, after: nil, group_after: nil)
        items = menu_items[key.to_sym].reject { |item| item.id == id.to_sym }
        menu_items[key.to_sym] = items + [MenuItem.new(id: id.to_sym, label: label, icon: icon, path: path,
          capability: capability, group: group, after: after, group_after: group_after)]
      end

      # A link in a top-level item's submenu (add_submenu_page): the core's
      # (:pages, :collections, :globals, :media, :block_types, :findings,
      # :approvals, :audit_log, :trash, :tools, :users, :roles, :settings) or
      # a plugin's. after: the label it follows there.
      def submenu(key, parent, label:, path:, capability: nil, after: nil)
        items = submenu_items[key.to_sym].reject { |item| item.parent == parent.to_sym && item.label == label }
        submenu_items[key.to_sym] = items + [SubmenuItem.new(parent: parent.to_sym, label: label, path: path,
          capability: capability, after: after)]
      end

      # An entry in the admin bar's "+ New" menu. after: the label it follows.
      def new_item(key, label:, path:, capability: nil, after: nil)
        items = new_items[key.to_sym].reject { |item| item.label == label }
        new_items[key.to_sym] = items + [NewItem.new(label: label, path: path, capability: capability, after: after)]
      end

      # The plugin's page in Settings, linked from its card in Settings ›
      # Plugins and listed under `group` ("Plugins" unless it names a core
      # group such as "Workspace"), after the section labelled `after`.
      def settings(key, label, path, description: nil, capability: nil, group: "Plugins", after: nil)
        settings_pages[key.to_sym] = SettingsPage.new(label: label, path: path, description: description,
          capability: capability, group: group, after: after)
      end

      # Capabilities for requires_capability and Role#permissions, shown as a
      # group in the role editor while the plugin is on (after the core group
      # `after`). Namespace them with the plugin's key ("hello:read").
      # defaults: what the built-in roles start with ({editor: […], site: […]},
      # DEFAULT_ROLES), for Permissions.defaults_for.
      def permissions(key, group, capabilities, after: nil, defaults: {})
        key = key.to_sym
        permission_groups[key][group] = Array(capabilities).map(&:to_s)
        permission_placements[key][group] = after
        defaults.each do |role, granted|
          raise ArgumentError, "unknown role #{role.inspect}" unless DEFAULT_ROLES.include?(role.to_sym)

          permission_defaults[key][role.to_sym] = Array(granted).map(&:to_s)
        end
      end

      # Counts in /api/manifest's `counts` and the backup summary
      # (backup: false for the manifest only): name: -> { Model.count }.
      def counts(key, after: nil, backup: true, **named)
        entries = counters[key.to_sym].reject { |counter| named.key?(counter.name) }
        counters[key.to_sym] = entries + named.map { |name, count| Counter.new(name: name, count: count, after: after, backup: backup) }
      end

      # A top-level key in /api/manifest, built by the lambda; after: the
      # core key it follows (:collections).
      def manifest_section(key, name, build, after: nil)
        entries = manifest_sections[key.to_sym].reject { |section| section.name == name.to_sym }
        manifest_sections[key.to_sym] = entries + [ManifestSection.new(name: name.to_sym, build: build, after: after)]
      end

      # A soft-deletable model the trash lists (Trash), by kind ("form"): the
      # model's class name, the filter's label, and meta: ->(record) { {…} }
      # for what tells two trashed records apart.
      def trashable(key, kind, model, label:, meta: nil, after: nil)
        entries = trash_kinds[key.to_sym].reject { |entry| entry.kind == kind.to_s }
        trash_kinds[key.to_sym] = entries + [TrashKind.new(kind: kind.to_s, model: model.to_s, label: label, meta: meta, after: after)]
      end

      # A RecurringTasks::Recipe subclass, by class name, offered in Tools ›
      # Schedules; after: the recipe key it follows.
      def recurring_recipe(key, recipe, after: nil)
        entries = recurring_recipes[key.to_sym].reject { |entry| entry.recipe == recipe.to_s }
        recurring_recipes[key.to_sym] = entries + [RecurringRecipe.new(recipe: recipe.to_s, after: after)]
      end

      # Events the plugin announces (Eventable#announce), offered to
      # webhooks under `label` and published in-process like the core's.
      # after: the event they follow in Webhook.events (the list /api/webhooks
      # returns). deploy: true when the event changes the public site, so it
      # schedules a rebuild like a publish does.
      #
      # A webhook may subscribe to the events of any installed plugin, on or
      # off — switching a plugin off mustn't make its webhooks invalid — but
      # the webhook form only offers the events of plugins that are on.
      def webhook_events(key, label, events, after: nil, deploy: false)
        webhook_event_groups[key.to_sym] = WebhookEventGroup.new(label: label, events: Array(events).map(&:to_s),
          after: after, deploy: deploy)
      end

      # Per-event criteria a webhook may carry in `event_filters[event]` (Forms
      # narrows submission.created to chosen forms). permit: ->(raw) { hash or
      # nil } turns submitted params into the stored shape — nothing else is
      # kept; validate: ->(value, errors) adds to the webhook's errors; match:
      # ->(value, payload) { bool } decides a delivery (value nil: no filter).
      # Like webhook_events, a filter holds whether its plugin is on or off.
      def webhook_event_filter(key, event, permit:, validate:, match:)
        webhook_event_filters[key.to_sym][event.to_s] = WebhookEventFilter.new(permit: permit, validate: validate, match: match)
      end

      # The filter registered for `event` by any installed plugin, or nil.
      def webhook_event_filter_for(event)
        webhook_event_filters.each_value { |filters| return filters[event.to_s] if filters.key?(event.to_s) }
        nil
      end

      # Something the core reads if a plugin supplies it, by name (the site
      # audit's :consent_config, :scripts, :published_forms). The core copes
      # with nil.
      def provide(key, name, value)
        providers[key.to_sym][name.to_sym] = value
      end

      # A stylesheet from the plugin's app/assets/stylesheets, linked on every
      # admin page while it's on.
      def stylesheet(key, name)
        stylesheets[key.to_sym] |= [name]
      end

      # Work to run every night (PluginsNightlyJob).
      def nightly(key, task)
        nightly_tasks[key.to_sym] = task
      end

      # Work to run every `every` minutes, on the minute (PluginsMinutelyJob,
      # which runs every minute). Each task is named, so a plugin can have a
      # scheduler and a reaper that fail independently. Keep a task to
      # enqueueing a job: the minutely job runs them one after another.
      def minutely(key, name, task, every: 1)
        minutely_tasks[key.to_sym][name.to_sym] = MinutelyTask.new(task: task, every: Integer(every))
      end

      # What a plugin sets up on a site: run by SiteBootstrap on a fresh
      # install while the plugin is on, and the first time someone switches
      # it on here. Must be idempotent (a re-run changes nothing).
      def bootstrap(key, task)
        bootstrap_tasks[key.to_sym] = task
      end

      # An endpoint the plugin adds under /api/<key>/, listed with the plugin
      # in /api/manifest so the CLI and agents find it.
      def api(key, path, description:)
        api_endpoints[key.to_sym][path] = description
      end

      # Tools for an agent capability, and (catalog:) the capability's entry in
      # the Agents builder and run brief: {group:, label:, capability:,
      # commands:, after:}. A plugin that owns the tools owns the entry, so a
      # run never sees a capability whose tools are switched off.
      def agent_tool(key, capability_group, tools, catalog: nil)
        agent_tools[key.to_sym][capability_group.to_s] = Array(tools)
        agent_capabilities[key.to_sym][capability_group.to_s] = catalog if catalog
      end

      # {capability key => catalog entry} of every installed plugin, on or
      # off: what a saved agent may keep in its capability keys.
      def installed_agent_capabilities = agent_capabilities.values.reduce({}, :merge)

      # {capability key => catalog entry} of the enabled plugins: what the
      # builder offers and a run's brief lists.
      def enabled_agent_capabilities = merged(agent_capabilities)

      def report_definition(key, report_key, definition)
        report_definitions[key.to_sym][report_key.to_s] = definition
      end

      def importer(key, source, adapter)
        importers[key.to_sym][source.to_s] = adapter
      end

      def script_preset(key, preset_key, preset)
        script_presets[key.to_sym][preset_key.to_s] = preset
      end

      # Block types the plugin ships (the same hashes BlockType::Defaults
      # holds), and the npm package with their Astro components.
      def block_types(key, block_types, package: nil)
        block_type_packs[key.to_sym] = BlockTypePack.new(block_types: Array(block_types), package: package)
      end

      # A field type for collection and page schemas: a validator (callable
      # taking the value, returning error strings) and the ERB editor partial.
      def field_type(key, type, validator:, partial:)
        field_types[key.to_sym][type.to_s] = FieldType.new(validator: validator, partial: partial)
      end

      # A Deploys::Provider subclass, offered in Settings › Deploy.
      def deploy_provider(key, provider_key, provider)
        deploy_providers[key.to_sym][provider_key.to_s] = provider
      end

      # --- state ------------------------------------------------------------

      # On in Settings, compatible with this core, and every plugin it depends
      # on enabled too. `seen` stops a dependency cycle from recursing forever
      # (a plugin in one is off).
      def enabled?(key, seen = Set.new)
        key = key.to_sym
        manifest = manifests[key] or return false
        return false if seen.include?(key)

        switched_on?(manifest) && manifest.compatible? && missing_dependencies(key, seen | [key]).empty?
      end

      # On in Settings, whatever its dependencies say.
      def switched_on?(manifest)
        states.fetch(manifest.key.to_s) { unset_state(manifest) } == true
      end

      # Nobody has switched it yet: its manifest's default, or on for good
      # when the install already holds its data (adopt_if).
      #
      # Adopting a plugin adopts the plugins it depends on that nobody has
      # switched either — an install that used agents before they were a
      # plugin used what they run on, too.
      def unset_state(manifest)
        return true if manifest.enabled_by_default
        return false unless manifest.adopt_if && adopted?(manifest)

        adopted = [manifest.key.to_s] + unset_dependencies(manifest)
        Setting.set(SETTING_KEY, adopted.index_with(true))
        Current.plugin_states = nil
        true
      end

      # Keys of the plugins `manifest` depends on, directly or not, that
      # nobody has switched on or off.
      def unset_dependencies(manifest, seen = Set.new([manifest.key]))
        manifest.depends_on.flat_map do |key|
          dependency = manifests[key]
          next [] if dependency.nil? || seen.include?(key) || states.key?(key.to_s)

          [key.to_s] + unset_dependencies(dependency, seen | [key])
        end.uniq
      end

      def missing_dependencies(key, seen = Set.new([key.to_sym]))
        manifest = manifests[key.to_sym] or return []
        manifest.depends_on.reject { |dependency| enabled?(dependency, seen) }
      end

      # Returns what switching it on granted the built-in roles (see
      # grant_default_permissions), {} otherwise.
      def switch!(key, on:)
        manifest = manifests[key.to_sym] or raise ArgumentError, "no plugin #{key.inspect}"

        first_time = !Setting.get(SETTING_KEY).key?(manifest.key.to_s)
        Setting.set(SETTING_KEY, {manifest.key.to_s => on})
        Current.plugin_states = nil
        return {} unless on && first_time

        bootstrap_tasks[manifest.key]&.call
        install_block_type_pack(manifest)
        grant_default_permissions(manifest)
      end

      # The first time a plugin is switched on, its block types join the
      # site's (the ones the site doesn't have yet; see BlockType.install_plugin_pack).
      def install_block_type_pack(manifest)
        pack = block_type_packs[manifest.key] or return
        ::BlockType.install_plugin_pack(manifest.key, pack.block_types)
      end

      # The first time someone switches a plugin on here, the built-in roles
      # (SiteBootstrap's Editor, Author, Production site and Agent, by name)
      # get the capabilities its `permissions … defaults:` names that they
      # don't hold yet — as a fresh install seeding with it on would have
      # given them. Never revokes. Not for a plugin that starts on (its
      # defaults were seeded with the roles) or one an upgrade adopted (the
      # roles already had its capabilities), and not on a later switch-on, so
      # a capability someone took away stays away.
      # Returns {role name => [capabilities added]}.
      def grant_default_permissions(manifest)
        return {} if manifest.enabled_by_default

        defaults = permission_defaults[manifest.key]
        built_in_roles.each_with_object({}) do |(name, role_key), granted|
          role = Role.find_by(name: name) or next
          missing = defaults.fetch(role_key, []) - Array(role.permissions)
          next if missing.empty? || role.admin?

          role.update!(permissions: Array(role.permissions) + missing)
          granted[name] = missing
        end
      end

      # Setting "plugins", read once a request (Current).
      def states
        Current.plugin_states ||= Setting.get(SETTING_KEY)
      end

      # --- what enabled plugins add --------------------------------------

      def enabled_manifests = manifests.values.select { enabled?(it.key) }
      def enabled_slots(name) = slots[name.to_sym].select { |key, _| enabled?(key) }
      def enabled_menu_items = menu_items.select { |key, _| enabled?(key) }.values.flatten
      def enabled_submenu_items = submenu_items.select { |key, _| enabled?(key) }.values.flatten
      def enabled_new_items = new_items.select { |key, _| enabled?(key) }.values.flatten
      def enabled_settings_pages = settings_pages.select { |key, _| enabled?(key) }
      def enabled_stylesheets = stylesheets.select { |key, _| enabled?(key) }.values.flatten
      def enabled_nightly_tasks = nightly_tasks.select { |key, _| enabled?(key) }
      def enabled_bootstrap_tasks = bootstrap_tasks.select { |key, _| enabled?(key) }

      # [["key:name", task], …] of the enabled plugins' minutely tasks due at `at`.
      def due_minutely_tasks(at = Time.current)
        minutely_tasks.select { |key, _| enabled?(key) }.flat_map do |key, tasks|
          tasks.filter_map { |name, entry| ["#{key}:#{name}", entry.task] if entry.due?(at) }
        end
      end
      def enabled_permission_groups = permission_groups.select { |key, _| enabled?(key) }.values.reduce({}, :merge)
      def enabled_agent_tools = merged(agent_tools)
      def enabled_report_definitions = merged(report_definitions)
      def enabled_importers = merged(importers)
      def enabled_script_presets = merged(script_presets)
      def enabled_field_types = merged(field_types)
      def enabled_deploy_providers = merged(deploy_providers)
      def enabled_block_type_packs = block_type_packs.select { |key, _| enabled?(key) }
      def enabled_counters = listed(counters)
      def enabled_manifest_sections = listed(manifest_sections)
      def enabled_trash_kinds = listed(trash_kinds)
      def enabled_recurring_recipes = listed(recurring_recipes)

      # Webhook events of every installed plugin, on or off, as arrange
      # additions ([[event, event, after], …]) — each follows the one before it
      # in its group, the first follows the group's `after`.
      def webhook_event_additions
        webhook_event_groups.values.flat_map do |group|
          group.events.each_with_index.map { |event, index| [event, event, index.zero? ? group.after : group.events[index - 1]] }
        end
      end

      # The groups the webhook form offers: [[label, events], …] of plugins that are on.
      def enabled_webhook_event_groups
        webhook_event_groups.select { |key, _| enabled?(key) }.values.map { |group| [group.label, group.events] }
      end

      # Plugin events that schedule a site rebuild (webhook_events … deploy: true).
      def deploy_webhook_events = webhook_event_groups.values.select(&:deploy).flat_map(&:events)

      # What the built-in role (DEFAULT_ROLES) starts with from the plugins
      # that are on.
      def enabled_permission_defaults(role)
        permission_defaults.select { |key, _| enabled?(key) }.values.flat_map { it.fetch(role.to_sym, []) }
      end

      # The permission groups the role editor offers, with the core group each
      # follows: [[group, capabilities, after], …].
      def enabled_permission_placements
        permission_groups.select { |key, _| enabled?(key) }.flat_map do |key, groups|
          groups.map { |group, capabilities| [group, capabilities, permission_placements[key][group]] }
        end
      end

      # The value an enabled plugin provides under `name` (a lambda is
      # called), or nil.
      def provided(name)
        providers.each do |key, provisions|
          next unless provisions.key?(name.to_sym) && enabled?(key)

          value = provisions[name.to_sym]
          return value.respond_to?(:call) ? value.call : value
        end
        nil
      end

      # Core items followed by additions, each addition placed right after the
      # item its `after` names (after earlier additions to the same place), or
      # at the end. core: [[id, value], …]; additions: [[id, value, after], …].
      # Returns [[id, value], …].
      #
      # `after` may name another addition, and may be a list of choices, the
      # first present winning. An addition whose choice is another addition
      # not placed yet waits for it, so the order plugins register in (their
      # gems load alphabetically) doesn't decide where things land.
      def arrange(core, additions)
        list = core.map { |id, value| [id, value, nil, false] }
        pending = additions.map { |id, value, after| [id, value, Array(after)] }

        until pending.empty?
          placed = pending.select do |id, value, anchors|
            anchor = anchors.find { |candidate| candidate == START || placed_in?(list, candidate) || waiting?(pending, candidate, id) }
            next false if anchor && anchor != START && !placed_in?(list, anchor)

            insert_after(list, id, value, anchor)
            true
          end
          # A cycle (two additions each waiting for the other): the rest go last.
          if placed.empty?
            pending.each { |id, value, _| insert_after(list, id, value, nil) }
            break
          end
          pending -= placed
        end

        list.map { |id, value, *| [id, value] }
      end

      # Every capability any installed plugin declares, on or off, so a
      # controller's requires_capability resolves at load time.
      def capabilities = permission_groups.values.flat_map(&:values).flatten.uniq

      # For /api/manifest: what this install has switched on.
      def manifest_listing
        enabled_manifests.sort_by(&:name).map do |manifest|
          {key: manifest.key.to_s, name: manifest.name, version: manifest.version,
           endpoints: api_endpoints[manifest.key].map { |path, description| {path: path, description: description} }}
        end
      end

      # What a plugin adds, in words, for Settings › Plugins.
      def additions(key)
        key = key.to_sym
        slots.filter_map { |name, entries| "Slot: #{SLOT_NAMES.fetch(name, name.to_s.humanize)}" if entries.key?(key) } +
          menu_items[key].map { "Menu: #{it.group} › #{it.label}" } +
          submenu_items[key].map { "Submenu: #{it.parent.to_s.humanize} › #{it.label}" } +
          new_items[key].map { "New: #{it.label}" } +
          Array(settings_pages[key]&.label&.then { "Settings: #{it}" }) +
          permission_groups[key].keys.map { "Permissions: #{it}" } +
          api_endpoints[key].keys.map { "API: #{it}" } +
          Array(("Nightly task" if nightly_tasks.key?(key))) +
          minutely_tasks[key].map { |name, entry| "Every #{entry.every == 1 ? "minute" : "#{entry.every} minutes"}: #{name.to_s.humanize.downcase}" } +
          Array(("Setup on install" if bootstrap_tasks.key?(key))) +
          agent_tools[key].keys.map { "Agent tools: #{it}" } +
          report_definitions[key].keys.map { "Report: #{it}" } +
          importers[key].keys.map { "Importer: #{it}" } +
          script_presets[key].keys.map { "Script preset: #{it}" } +
          Array(block_type_packs[key]&.then { "Block types: #{it.block_types.size}" }) +
          trash_kinds[key].map { "Trash: #{it.label}" } +
          recurring_recipes[key].map { "Schedule: #{it.klass.title}" } +
          field_types[key].keys.map { "Field type: #{it}" } +
          deploy_providers[key].keys.map { "Deploy provider: #{it}" }
      end

      private

      # [[role name, DEFAULT_ROLES key], …] for the roles a fresh install seeds.
      def built_in_roles
        (SiteBootstrap::HUMAN_ROLES + SiteBootstrap::MACHINE_ROLES).map { [it[:name], it[:defaults]] }
      end

      def placed_in?(list, id) = list.any? { |existing, *| existing == id }

      def waiting?(pending, id, own_id) = id != own_id && pending.any? { |pending_id, *| pending_id == id }

      def insert_after(list, id, value, anchor)
        index = anchor.nil? ? nil : list.index { |existing, *| existing == anchor }
        if anchor == START
          position = 0
          position += 1 while position < list.size && list[position][3] && list[position][2] == START
          list.insert(position, [id, value, anchor, true])
        elsif index
          position = index + 1
          position += 1 while position < list.size && list[position][3] && list[position][2] == anchor
          list.insert(position, [id, value, anchor, true])
        else
          list << [id, value, anchor, true]
        end
      end

      def merged(registry)
        registry.select { |key, _| enabled?(key) }.values.reduce({}, :merge)
      end

      def listed(registry)
        registry.select { |key, _| enabled?(key) }.values.flatten
      end

      # A lookup that can't run yet (tables missing while the database is
      # being prepared) answers no.
      def adopted?(manifest)
        adoptions = (Current.plugin_adoptions ||= {})
        return adoptions[manifest.key] if adoptions.key?(manifest.key)

        adoptions[manifest.key] = begin
          manifest.adopt_if.call.present?
        rescue StandardError
          false
        end
      end
    end
  end
end
