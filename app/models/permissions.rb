# frozen_string_literal: true

# Single source of truth for the capability catalog. Capabilities are
# `<resource>:<action>` strings stored on `Role.permissions` and checked by
# `User#can?`. The `system` admin role is a special case that holds all
# capabilities by way of `manage:all` — it doesn't enumerate them.
#
# Adding a new capability is a two-step change:
#   1. List it here (in CATALOG), or for a plugin with
#      `Cms::Plugins.permissions`.
#   2. Declare `requires_capability "..."` on the controller(s) that use it.
module Permissions
  WILDCARD = "manage:all"

  # Catalog grouped by resource for the UI. Order matters — UI renders
  # resources in this order. Actions are: read, write, delete, publish.
  CATALOG = {
    "Pages"        => %w[pages:read pages:write pages:delete pages:publish],
    "Collections"  => %w[collections:read collections:write collections:delete],
    "Entries"      => %w[entries:read entries:write entries:delete entries:publish],
    "Block types"  => %w[block_types:read block_types:write block_types:delete],
    # `globals:publish` gates writing a global that is already live. Globals
    # have no draft state — nav, footer and brand are in front of visitors the
    # moment they change — so it's the publish capability that decides whether
    # an API write applies or files a revision for review.
    "Globals"      => %w[globals:read globals:write globals:publish globals:delete],
    "Assets"       => %w[assets:read assets:write assets:delete],
    "Webhooks"     => %w[webhooks:read webhooks:write webhooks:delete],
    "Redirects"    => %w[redirects:read redirects:write redirects:delete],
    "Users"        => %w[users:read users:write users:delete],
    "Roles"        => %w[roles:read roles:write roles:delete],
    "Settings"     => %w[settings:read settings:write],
    # Advisory findings from a run. `recommendations:write` lets an agent
    # file one; `recommendations:resolve` is the human decision.
    "Recommendations" => %w[recommendations:read recommendations:write recommendations:resolve],
    "Audit log"    => %w[audit_log:read],
    "Trash"        => %w[trash:read trash:write],
    "Tools"        => %w[tools:use]
  }.freeze

  ALL = CATALOG.values.flatten.freeze

  # Sensible defaults for the canned roles — the core's part. A role is
  # seeded with `defaults_for`, which adds what enabled plugins grant it.
  #
  # The two human roles below — Editor and Author — are about content. They
  # deliberately hold NO `reports:*`, `agents:*` or `recommendations:*`:
  # reports spend money, agents act on the site unattended, and findings are
  # the agents' output. Those are the administrator's to see and to delegate,
  # which the Roles page does — a site that wants an editor watching the
  # Marketer's Report grants `reports:read` to that role on purpose.
  EDITOR_DEFAULT = %w[
    pages:read pages:write pages:publish
    collections:read
    entries:read entries:write entries:publish
    block_types:read
    globals:read globals:write globals:publish
    assets:read assets:write
    webhooks:read
    redirects:read
    settings:read
    audit_log:read
    trash:read trash:write
  ].freeze

  # Roles for machines rather than people (see ServiceToken).
  #
  # A published site only renders: it needs to read content and nothing else,
  # so a leaked PRODUCTION_TOKEN reads what the site already shows the world.
  SITE_DEFAULT = %w[
    pages:read
    collections:read
    entries:read
    block_types:read
    globals:read
    assets:read
    redirects:read
  ].freeze

  # An agent or script: writes content, never publishes it. Paired with the
  # write gate, that means every edit it makes to an already-live record
  # becomes a revision awaiting human review.
  AGENT_DEFAULT = %w[
    pages:read pages:write
    collections:read
    entries:read entries:write
    block_types:read
    globals:read globals:write
    assets:read assets:write
    redirects:read
    settings:read
    recommendations:read recommendations:write
  ].freeze

  AUTHOR_DEFAULT = %w[
    pages:read pages:write
    collections:read
    entries:read entries:write
    block_types:read
    globals:read
    assets:read assets:write
    settings:read
  ].freeze

  module_function

  CORE_DEFAULTS = {editor: EDITOR_DEFAULT, author: AUTHOR_DEFAULT, site: SITE_DEFAULT, agent: AGENT_DEFAULT}.freeze

  # The core's catalog plus the groups of plugins that are switched on, each
  # where its plugin placed it — what the role editor offers.
  def catalog
    additions = Cms::Plugins.enabled_permission_placements
    Cms::Plugins.arrange(CATALOG.to_a, additions).to_h
  end

  # What a built-in role (:editor, :author, :site, :agent) starts with: the
  # core's defaults and what the enabled plugins grant it.
  def defaults_for(role)
    (CORE_DEFAULTS.fetch(role.to_sym) | Cms::Plugins.enabled_permission_defaults(role)).dup
  end

  # What a role can hold right now: the core's capabilities and those of the
  # plugins that are on.
  def all
    # In the role editor's order, so a wildcard token lists its capabilities
    # with each plugin's where the plugin placed its group.
    catalog.values.flatten | ALL
  end

  # Anything the core or ANY installed plugin declares, on or off: a
  # controller's requires_capability resolves at load time, and a role keeps
  # a plugin capability while the plugin is switched off.
  def known?(capability)
    capability == WILDCARD || ALL.include?(capability) || Cms::Plugins.capabilities.include?(capability)
  end
end
