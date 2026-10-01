# frozen_string_literal: true

module Agents
  # What an agent may do, grouped for the builder UI.
  #
  # Lumin/ads has a tool catalog because its tools are Ruby objects the server
  # instantiates and executes. Nothing like that exists here, and shouldn't:
  # the CMS's tool surface is the `cms` CLI and the HTTP API behind it, and a
  # harness already has both. So an entry is not a class to instantiate — it
  # is a named piece of the CLI, the capability the token must carry to use
  # it, and the commands to put in the brief.
  #
  # THE CATALOG IS NOT THE GATE. `Role`/`Permissions` is — a token can only
  # ever do what its role allows, whatever an agent's `capability_keys` say.
  # Selecting keys here shapes what the agent is *told* to do and keeps the
  # brief honest; it can't widen a token. `#missing_capabilities` is what
  # surfaces the mismatch, so an agent granted a key its worker's role can't
  # use says so on the row instead of discovering it as a 403 mid-run.
  module CapabilityCatalog
    READ = {
      "manifest" => {
        label: "Site manifest (collections, schemas, block types)",
        capability: "pages:read",
        commands: ["cms manifest", "cms brand"]
      },
      "read_pages" => {
        label: "Read pages",
        capability: "pages:read",
        commands: ["cms pages [--status published] [--locale en]", "cms page <path>"]
      },
      "read_entries" => {
        label: "Read collections and entries",
        capability: "entries:read",
        commands: ["cms collections", "cms entries <collection>", "cms entry <collection> <slug>"]
      },
      "read_globals" => {
        label: "Read globals (nav, footer, scripts)",
        capability: "globals:read",
        commands: ["cms globals", "cms global <slug>"]
      },
      "search" => {
        label: "Full-text search the site",
        capability: "pages:read",
        commands: ["cms search \"<query>\""]
      },
      "references" => {
        label: "What links to a record",
        capability: "pages:read",
        commands: ["cms refs Page <id>"]
      },
      "sitemap" => {
        label: "Read the sitemap",
        capability: "pages:read",
        commands: ["cms sitemap"]
      },
      "read_redirects" => {
        label: "Read redirect rules and hit counts",
        capability: "redirects:read",
        commands: ["cms redirects all"]
      },
      "read_assets" => {
        label: "Read the asset library",
        capability: "assets:read",
        commands: ["cms assets"]
      },
      "audit" => {
        label: "Read the audit log",
        capability: "audit_log:read",
        commands: ["cms audit"]
      }
    }.freeze

    # Writes. Every one of these is subject to the review gate: a token
    # without the matching `:publish` capability that edits an already-live
    # record gets a 202 and a revision, not a 200. That is the point — see
    # GatedWrites.
    WRITE = {
      "write_pages" => {
        label: "Create and edit pages",
        capability: "pages:write",
        commands: [
          "cms post /pages '{\"page\":{…}}'",
          "cms patch /pages/<path> '{\"page\":{…}}'"
        ]
      },
      "write_entries" => {
        label: "Create and edit collection entries",
        capability: "entries:write",
        commands: ["cms patch /collections/<c>/entries/<slug> - < entry.json"]
      },
      "write_globals" => {
        label: "Edit globals",
        capability: "globals:write",
        commands: ["cms patch /globals/<slug> '{\"global\":{…}}'"]
      },
      "write_assets" => {
        label: "Upload assets",
        capability: "assets:write",
        commands: ["cms post /assets"]
      },
      "write_redirects" => {
        label: "Add redirect rules",
        capability: "redirects:write",
        commands: ["cms redirect add /old /new 301"]
      },
      "write_schema" => {
        label: "Edit field schemas",
        capability: "collections:write",
        commands: ["cms schema collection <slug> < fields.json"]
      }
    }.freeze

    # Deliberately its own group, and off by default.
    #
    # An agent that can publish is an agent whose work no one reviews, which
    # removes the only safety property this design has. It exists because a
    # trusted maintenance agent (pruning expired notices, say) is a real case
    # — but it should be a decision someone made on purpose.
    PUBLISH = {
      "publish_pages" => {
        label: "Publish and unpublish pages",
        capability: "pages:publish",
        commands: ["cms publish <path>", "cms unpublish <path>"]
      },
      "publish_entries" => {
        label: "Publish and unpublish entries",
        capability: "entries:publish",
        commands: ["cms entry-status <collection> published <slug>"]
      }
    }.freeze

    # How an agent hands work back to a human. Findings and review requests
    # are the outputs of an agent that can't publish, so this group is what
    # makes a review-gated agent useful rather than merely safe.
    REPORT = {
      "recommend" => {
        label: "File findings for review (content gaps, technical SEO)",
        capability: "recommendations:write",
        commands: ["cms recommend <kind> \"<title>\" [--subject page:<path>] [--impact 1-5]"]
      },
      "review_request" => {
        label: "Ask a human to review and publish a draft",
        capability: "pages:read",
        commands: ["cms review request Page <path> \"<note>\""]
      }
    }.freeze

    OPERATIONS = {
      "deploy" => {
        label: "Check and trigger site rebuilds",
        capability: "tools:use",
        commands: ["cms deploy", "cms deploy now"]
      },
      "submissions" => {
        label: "Read form submissions",
        capability: "submissions:read",
        commands: ["cms submissions"]
      },
      "webhooks" => {
        label: "Read webhook configuration",
        capability: "webhooks:read",
        commands: ["cms webhooks"]
      }
    }.freeze

    READ_GROUP = "Read"
    WRITE_GROUP = "Write (goes to review)"
    PUBLISH_GROUP = "Publish directly — skips review"

    # The core's entries. Plugins add their own with their agent tools
    # (Cms::Plugins.agent_tool …, catalog:), placed after the entry they name.
    GROUPS = {
      READ_GROUP => READ,
      WRITE_GROUP => WRITE,
      "Report back" => REPORT,
      PUBLISH_GROUP => PUBLISH,
      "Operations" => OPERATIONS
    }.freeze

    ALL = GROUPS.values.reduce(:merge).freeze

    module_function

    # The builder's groups: the core's, with the enabled plugins' entries in
    # place. A switched-off plugin's capabilities aren't offered.
    def groups
      additions = Cms::Plugins.enabled_agent_capabilities
      GROUPS.to_h do |name, entries|
        mine = additions.select { |_, entry| entry[:group] == name }
          .map { |key, entry| [key, entry.except(:group, :after), entry[:after]] }
        [name, Cms::Plugins.arrange(entries.to_a, mine).to_h]
      end
    end

    # What a run may be granted: the core's and the enabled plugins'.
    def all = groups.values.reduce(:merge)

    # Everything an agent may keep in its keys, a switched-off plugin's
    # included, so saving an agent while a plugin is off doesn't drop them.
    def known
      ALL.merge(Cms::Plugins.installed_agent_capabilities.transform_values { it.except(:group, :after) })
    end

    # A sensible read-only starting point for a blank agent.
    def default_keys = groups[READ_GROUP].keys + %w[recommend review_request]

    def fetch(key) = known[key.to_s]

    def valid_keys(keys) = Array(keys).map(&:to_s) & known.keys

    # The keys a run can use now: a switched-off plugin's are left out.
    def usable_keys(keys) = Array(keys).map(&:to_s) & all.keys

    def label(key) = known.dig(key.to_s, :label)

    def labels(keys) = valid_keys(keys).map { |key| label(key) }

    # The capabilities a role must hold for these keys to be usable.
    def capabilities_for(keys)
      usable_keys(keys).filter_map { |key| all.dig(key, :capability) }.uniq
    end

    # Which of `keys` the given role can't actually perform. Empty is the
    # happy path; anything else is an agent configured to do something its
    # worker will be refused.
    def missing_capabilities(keys, role)
      return capabilities_for(keys) if role.nil?

      capabilities_for(keys).reject { |capability| role.has_capability?(capability) }
    end

    # Keys that write to live content — used to explain, on the agent form,
    # why this agent's output will land in the review queue.
    def writes?(keys) = usable_keys(keys).intersect?(groups[WRITE_GROUP].keys)

    def publishes?(keys) = usable_keys(keys).intersect?(groups[PUBLISH_GROUP].keys)
  end
end
