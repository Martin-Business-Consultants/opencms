# frozen_string_literal: true

# The "fresh install" recipe — every step needed to take an empty database
# to a usable site. Called by:
#
#   - SiteSetup, which a new install runs once (`bin/rails cms:bootstrap`)
#   - db/seeds.rb for the local-dev demo site (which then overlays its own
#     opinionated demo content on top)
#
# The split with BlockType::Defaults: BlockType::Defaults owns the block-type
# starter pack (one concern). SiteBootstrap composes it with the other
# bootstrap concerns (globals, site title, an opening home page).
#
# Idempotent: every step uses find_or_initialize_by, and globals only seed
# their data on first creation so editor changes are never trampled.
module SiteBootstrap
  # The three editorial singletons every site needs. Schemas are real
  # (so the form renders something), data is intentionally minimal — a
  # single visible row each so the public site renders, plus an obvious
  # invitation to edit. No industry-specific content.
  STARTER_GLOBALS = [
    {
      slug: "nav", name: "Navigation",
      description: "Top navigation menu items.",
      icon: "Menu",
      schema: {
        "fields" => [
          {"name" => "items", "label" => "Items", "type" => "repeater", "required" => true,
           "of" => [
             {"name" => "label", "label" => "Label", "type" => "string", "required" => true},
             {"name" => "link",  "label" => "Link",  "type" => "link",   "required" => true}
           ]}
        ]
      },
      data: {
        "items" => [
          {"label" => "Home", "link" => {"kind" => "page", "value" => "home"}}
        ]
      }
    },
    {
      slug: "footer", name: "Footer",
      description: "Footer columns, copyright, address.",
      icon: "PanelBottom",
      schema: {
        "fields" => [
          {"name" => "columns", "label" => "Columns", "type" => "repeater",
           "of" => [
             {"name" => "heading", "label" => "Heading", "type" => "string"},
             {"name" => "items",   "label" => "Items",   "type" => "repeater",
              "of" => [
                {"name" => "label", "label" => "Label", "type" => "string", "required" => true},
                {"name" => "link",  "label" => "Link",  "type" => "link",   "required" => true}
              ]}
           ]},
          {"name" => "copyright", "label" => "Copyright text", "type" => "string"},
          {"name" => "address",   "label" => "Address",        "type" => "text"}
        ]
      },
      data: {
        "columns" => [
          {"heading" => "Legal", "items" => [
            {"label" => "Privacy", "link" => {"kind" => "url", "value" => "/privacy"}},
            {"label" => "Terms",   "link" => {"kind" => "url", "value" => "/terms"}}
          ]}
        ],
        "copyright" => "",
        "address"   => ""
      }
    },
    {
      slug: "scripts", name: "Scripts",
      description: "Named script blocks injected into <head> and before </body>. Privileged.",
      icon: "Code",
      schema: {
        "fields" => [
          {"name" => "items", "label" => "Scripts", "type" => "repeater",
           "help" => "Add one entry per script (analytics, pixels, fonts, etc.).",
           "of" => [
             {"name" => "name", "label" => "Name", "type" => "string", "required" => true,
              "help" => "Internal label, e.g. 'GA4', 'Meta Pixel'."},
             {"name" => "head", "label" => "Head", "type" => "text",
              "help" => "Pasted into <head>."},
             {"name" => "body", "label" => "Body", "type" => "text",
              "help" => "Pasted just before the closing </body> tag."}
           ]}
        ]
      },
      data: {"items" => []}
    }
  ].freeze

  # Bring the site up to "usable" state. `site_name` seeds the public-facing
  # title and the home page's hero — "Untitled site" if the caller didn't pass
  # one.
  def self.bootstrap!(site_name: "Untitled site")
    install_machine_roles!
    install_human_roles!
    install_block_types!
    install_general_setting!(site_name: site_name)
    install_github_setting!
    install_starter_globals!
    install_home_page!(site_name: site_name)
    install_plugins!
    nil
  end

  # The roles a ServiceToken is issued against. A machine credential should
  # carry the reach of its job and no more: a published site renders, so
  # read-only; an agent writes but never publishes, so its edits to live
  # records land in review instead of on the site.
  #
  # Names are the contract — SiteSetup and the migration for existing
  # sites both look them up by name. Permissions are only set on create, so
  # an operator who tunes one keeps their version. A role starts with
  # Permissions.defaults_for its `defaults:` (the core's part plus what
  # enabled plugins grant); `permissions:` is the core's part alone, which
  # the old seed_machine_roles migration reads.
  MACHINE_ROLES = [
    {
      name:        "Production site",
      description: "Read-only. The role behind a published site's PRODUCTION_TOKEN.",
      defaults: :site, permissions: Permissions::SITE_DEFAULT
    },
    {
      name:        "Agent",
      description: "Writes content but can't publish it — edits to live records go to review. " \
                   "The role behind USER_AGENT_TOKEN.",
      defaults: :agent, permissions: Permissions::AGENT_DEFAULT
    }
  ].freeze

  # The roles a person is given on day one. Admin is created lazily by
  # Role.system_admin; these two are the ordinary content roles, and neither
  # can see agents or reports — that stays with the administrator until they
  # grant it on the Roles page. Not `system`: a site may edit them.
  HUMAN_ROLES = [
    {name: "Editor",
     description: "Writes and publishes content. No access to agents or reports.",
     defaults: :editor, permissions: Permissions::EDITOR_DEFAULT},
    {name: "Author",
     description: "Writes content for an editor to publish. No access to agents or reports.",
     defaults: :author, permissions: Permissions::AUTHOR_DEFAULT}
  ].freeze

  def self.install_human_roles!
    HUMAN_ROLES.each do |attrs|
      role = Role.find_or_initialize_by(name: attrs[:name])
      next unless role.new_record?

      role.description = attrs[:description]
      role.permissions = Permissions.defaults_for(attrs[:defaults])
      role.system = false
      role.save!
    end
  end

  def self.install_machine_roles!
    MACHINE_ROLES.each do |attrs|
      role = Role.find_or_initialize_by(name: attrs[:name])
      next unless role.new_record?

      role.description = attrs[:description]
      role.permissions = Permissions.defaults_for(attrs[:defaults])
      role.save!
    end
  end

  def self.install_block_types!
    BlockType::Defaults.install!
  end

  # What the plugins that are on set up on a site (Cms::Plugins.bootstrap).
  # A plugin switched on later runs its own the first time it is.
  def self.install_plugins!
    Cms::Plugins.enabled_bootstrap_tasks.each_value(&:call)
  end

  def self.install_general_setting!(site_name:)
    return if Setting.exists?(key: "general")

    Setting.set("general", {
      "title"          => site_name,
      "description"    => "",
      "default_locale" => "en"
    })
  end

  # The `github` Setting carries `frontend_github_repo` — the repo
  # holding the Astro site this CMS publishes, as `owner/name`. It seeds blank
  # (we can't know it) but it must always be *present*, because that's what
  # makes it discoverable: an agent reading Settings finds the key and knows
  # to fill it in, instead of having to be told the concept exists.
  #
  # Only seeds when the key is absent, so a site that already recorded its
  # repo never gets blanked by a re-run. `Setting.set` merges, so the token
  # living under the same key is untouched either way.
  def self.install_github_setting!
    return if Setting.get("github").key?("frontend_github_repo")

    Setting.set("github", {"frontend_github_repo" => ""})
  end

  # Creates any starter global that's missing and leaves existing ones
  # completely alone.
  #
  # This used to re-assign `schema` on every run while preserving `data`. On a
  # site whose globals had been customised that combination is destructive:
  # the schema reverts to the starter shape while the customised data stays,
  # so either the editor's schema is silently lost or — if the data no longer
  # satisfies the reverted schema — `save!` raises and the whole bootstrap
  # fails. Re-running bootstrap on a live site (which `cms:bootstrap` does)
  # hit exactly that.
  #
  # Skipping existing globals still lets a later release introduce a NEW
  # starter global, which is the only reason to re-run this at all.
  def self.install_starter_globals!
    STARTER_GLOBALS.each do |attrs|
      g = Global.find_or_initialize_by(slug: attrs[:slug])
      next unless g.new_record?

      g.assign_attributes(
        name:        attrs[:name],
        description: attrs[:description],
        icon:        attrs[:icon],
        schema:      attrs[:schema],
        data:        attrs[:data]
      )
      g.save!
    end
  end

  # A draft home page with one Hero block. Draft so a brand-new site's
  # public site stays blank until they bless it; the editor still opens to a
  # populated canvas instead of an empty Pages list.
  def self.install_home_page!(site_name:)
    page = Page.find_or_initialize_by(slug: "home")
    return page unless page.new_record?

    page.assign_attributes(
      title:  site_name,
      status: "draft",
      locale: "en",
      blocks: [
        {"type" => "hero", "version" => 1, "data" => {
          "heading"    => site_name,
          "subheading" => "Replace this with one line that tells visitors what you do."
        }}
      ]
    )
    page.save!
    page
  end
end
