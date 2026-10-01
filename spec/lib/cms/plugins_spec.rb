# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cms::Plugins do
  after { %i[alpha beta cyclic_a cyclic_b future].each { forget_plugin(it) } }

  def register(key, **options)
    described_class.register(key, name: key.to_s.titleize, version: "0.1.0", description: "A test plugin.", **options)
  end

  describe "state" do
    it "starts off unless the manifest says otherwise, and follows the setting after that" do
      register :alpha
      register :beta, enabled_by_default: true

      expect(described_class.enabled?(:alpha)).to be(false)
      expect(described_class.enabled?(:beta)).to be(true)

      switch_plugin :alpha, on: true
      switch_plugin :beta, on: false

      expect(described_class.enabled?(:alpha)).to be(true)
      expect(described_class.enabled?(:beta)).to be(false)
      expect(Setting.get("plugins")).to include("alpha" => true, "beta" => false)
    end

    it "is off for a core version it doesn't support" do
      register :future, requires: ">= 99.0", enabled_by_default: true

      expect(described_class.manifests[:future]).not_to be_compatible
      expect(described_class.enabled?(:future)).to be(false)
    end

    it "waits for the plugins it depends on" do
      register :alpha, depends_on: [:beta], enabled_by_default: true
      register :beta

      expect(described_class.enabled?(:alpha)).to be(false)
      expect(described_class.missing_dependencies(:alpha)).to eq([:beta])

      switch_plugin :beta, on: true
      expect(described_class.enabled?(:alpha)).to be(true)
    end

    it "treats a dependency cycle as off rather than recursing" do
      register :cyclic_a, depends_on: [:cyclic_b], enabled_by_default: true
      register :cyclic_b, depends_on: [:cyclic_a], enabled_by_default: true

      expect(described_class.enabled?(:cyclic_a)).to be(false)
    end

    it "doesn't know a plugin that isn't registered" do
      expect(described_class.enabled?(:nope)).to be(false)
      expect { described_class.switch!(:nope, on: true) }.to raise_error(ArgumentError)
    end
  end

  describe "what a plugin adds" do
    before do
      register :alpha
      described_class.menu :alpha, :alpha, label: "Alpha", icon: "bolt", group: "Tools", path: -> { "/alpha" }
      described_class.submenu :alpha, :tools, label: "Alpha tools", path: -> { "/alpha/tools" }
      described_class.new_item :alpha, label: "Alpha", path: -> { "/alpha/new" }
      described_class.permissions :alpha, "Alpha", %w[alpha:read]
      described_class.agent_tool :alpha, "read_alpha", [Class.new]
      described_class.report_definition :alpha, "alpha_report", Class.new
      described_class.importer :alpha, "ghost", Class.new
      described_class.script_preset :alpha, "plausible", {name: "Plausible"}
      described_class.block_types :alpha, [{"slug" => "alpha_hero"}], package: "@acme/alpha-blocks"
      described_class.field_type :alpha, "rating", validator: ->(_) { [] }, partial: "alpha/fields/rating"
      described_class.deploy_provider :alpha, "netlify", Class.new(Deploys::Provider)
      described_class.api :alpha, "/api/alpha/things", description: "Things."
    end

    it "shows nothing while the plugin is off" do
      expect(described_class.enabled_menu_items.map(&:label)).not_to include("Alpha")
      expect(described_class.enabled_submenu_items.map(&:label)).not_to include("Alpha tools")
      expect(described_class.enabled_new_items.map(&:label)).not_to include("Alpha")
      expect(described_class.enabled_agent_tools).not_to have_key("read_alpha")
      expect(described_class.enabled_deploy_providers).not_to have_key("netlify")
      expect(described_class.manifest_listing.map { it[:key] }).not_to include("alpha")
      expect(Permissions.catalog).not_to have_key("Alpha")
    end

    it "shows all of it once the plugin is on" do
      switch_plugin :alpha, on: true

      expect(described_class.enabled_menu_items.map(&:label)).to include("Alpha")
      expect(described_class.enabled_submenu_items.map(&:label)).to include("Alpha tools")
      expect(described_class.enabled_new_items.map(&:label)).to include("Alpha")
      expect(described_class.enabled_agent_tools).to have_key("read_alpha")
      expect(described_class.enabled_report_definitions).to have_key("alpha_report")
      expect(described_class.enabled_importers).to have_key("ghost")
      expect(described_class.enabled_script_presets).to have_key("plausible")
      expect(described_class.enabled_block_type_packs[:alpha].package).to eq("@acme/alpha-blocks")
      expect(described_class.enabled_field_types).to have_key("rating")
      expect(Deploys.providers).to have_key("netlify")
      expect(described_class.manifest_listing).to include(
        {key: "alpha", name: "Alpha", version: "0.1.0",
         endpoints: [{path: "/api/alpha/things", description: "Things."}]}
      )
      expect(Permissions.catalog["Alpha"]).to eq(%w[alpha:read])
    end

    it "lets a controller declare its capabilities whether or not the plugin is on" do
      expect(Permissions.known?("alpha:read")).to be(true)
      expect(Permissions.all).not_to include("alpha:read")

      switch_plugin :alpha, on: true
      expect(Permissions.all).to include("alpha:read")
    end

    it "describes itself for Settings › Plugins" do
      expect(described_class.additions(:alpha)).to include(
        "Menu: Tools › Alpha", "Permissions: Alpha", "API: /api/alpha/things", "Deploy provider: netlify", "Field type: rating"
      )
    end
  end

  describe "adopting an install that already uses a plugin" do
    it "switches a plugin on, for good, when its data exists and nobody has switched it" do
      register :alpha, adopt_if: -> { true }

      expect(described_class.enabled?(:alpha)).to be(true)
      expect(Setting.get("plugins")).to include("alpha" => true)
    end

    it "leaves it off without data, and never overrides a choice someone made" do
      register :alpha, adopt_if: -> { false }
      expect(described_class.enabled?(:alpha)).to be(false)
      expect(Setting.get("plugins")).not_to have_key("alpha")

      register :beta, adopt_if: -> { true }
      switch_plugin :beta, on: false
      expect(described_class.enabled?(:beta)).to be(false)
    end

    it "answers no when the check can't run yet" do
      register :alpha, adopt_if: -> { raise ActiveRecord::StatementInvalid, "no such table" }

      expect(described_class.enabled?(:alpha)).to be(false)
    end
  end

  describe "placing additions among the core's own" do
    it "puts each addition after the item it names, in registration order, else last" do
      core = [[:a, 1], [:b, 2], [:c, 3]]
      additions = [[:x, 9, :a], [:y, 8, :a], [:z, 7, :missing], [:w, 6, :x]]

      expect(described_class.arrange(core, additions).map(&:first)).to eq(%i[a x w y b c z])
    end

    it "waits for an addition it names, whichever registered first" do
      core = [[:a, 1], [:b, 2]]
      # :late names :early, which registers after it (plugins load alphabetically).
      additions = [[:late, 1, :early], [:early, 2, :a]]

      expect(described_class.arrange(core, additions).map(&:first)).to eq(%i[a early late b])
    end

    it "takes the first choice that's there, falling back when a plugin is off" do
      core = [[:globals, 1], [:assets, 2]]

      with_forms = [[:commerce, 1, %i[forms globals]], [:forms, 2, :globals]]
      expect(described_class.arrange(core, with_forms).map(&:first)).to eq(%i[globals forms commerce assets])

      without_forms = [[:commerce, 1, %i[forms globals]]]
      expect(described_class.arrange(core, without_forms).map(&:first)).to eq(%i[globals commerce assets])
    end

    it "puts additions that wait on each other last rather than looping" do
      core = [[:a, 1]]
      additions = [[:x, 1, :y], [:y, 2, :x]]

      expect(described_class.arrange(core, additions).map(&:first)).to eq(%i[a x y])
    end

    it "orders the role editor, the trash, the schedules and the manifest's counts that way" do
      register :alpha, enabled_by_default: true
      described_class.permissions :alpha, "Alpha", %w[alpha:read], after: "Pages", defaults: {site: %w[alpha:read]}
      described_class.trashable :alpha, "alpha", "Page", label: "Alphas", after: "page", meta: ->(record) { {id: record.id} }
      described_class.recurring_recipe :alpha, "RecurringTasks::Recipes::SitemapPing", after: "trash_purge"
      described_class.counts :alpha, after: :pages, alphas: -> { 42 }
      described_class.provide :alpha, :greeting, -> { "hi" }

      expect(Permissions.catalog.keys.first(2)).to eq(["Pages", "Alpha"])
      expect(Permissions.defaults_for(:site)).to include("alpha:read")
      expect(Trash.labels.keys.first(2)).to eq(%w[page alpha])
      expect(Trash.meta("alpha", Page.new(id: 7))).to eq({id: 7})
      expect(RecurringTasks::Catalog.all.map(&:key).first(2)).to eq(%w[trash_purge sitemap_ping])
      expect(described_class.enabled_counters.map(&:name)).to include(:alphas)
      expect(described_class.provided(:greeting)).to eq("hi")

      switch_plugin :alpha, on: false
      expect(Permissions.catalog).not_to have_key("Alpha")
      expect(Trash.labels).not_to have_key("alpha")
      expect(described_class.provided(:greeting)).to be_nil
    end

    it "refuses a default for a role that isn't built in" do
      register :alpha
      expect { described_class.permissions :alpha, "Alpha", %w[alpha:read], defaults: {janitor: %w[alpha:read]} }
        .to raise_error(ArgumentError)
    end
  end

  it "registers again on a code reload without duplicating" do
    2.times do
      register :alpha
      described_class.menu :alpha, :alpha, label: "Alpha", icon: "bolt", group: "Tools", path: -> { "/alpha" }
      described_class.submenu :alpha, :tools, label: "Alpha tools", path: -> { "/alpha/tools" }
      described_class.stylesheet :alpha, "alpha/alpha"
    end

    expect(described_class.menu_items[:alpha].size).to eq(1)
    expect(described_class.submenu_items[:alpha].size).to eq(1)
    expect(described_class.stylesheets[:alpha]).to eq(["alpha/alpha"])
  end
  describe "arrange with after: :start" do
    it "puts an addition before the core items, in the order they came" do
      core = [["Redirects", 1], ["Backup", 2]]
      additions = [["Import", 3, :start], ["Export", 4, :start], ["Later", 5, "Redirects"]]

      expect(described_class.arrange(core, additions).map(&:first)).to eq(%w[Import Export Redirects Later Backup])
    end
  end

  describe "switching a plugin on for the first time" do
    let(:editor) { Role.find_by!(name: "Editor") }
    let(:agent) { Role.find_by!(name: "Agent") }

    before do
      register :alpha
      described_class.permissions :alpha, "Alpha", %w[alpha:read alpha:write], defaults: {editor: %w[alpha:read alpha:write], agent: %w[alpha:read]}
      Role.find_or_initialize_by(name: "Editor").update!(permissions: %w[pages:read])
      Role.find_or_initialize_by(name: "Agent").update!(permissions: %w[pages:read alpha:read])
    end

    it "gives the built-in roles its defaults they don't have, and says which" do
      granted = described_class.switch!(:alpha, on: true)

      expect(granted).to eq("Editor" => %w[alpha:read alpha:write])
      expect(editor.reload.permissions).to eq(%w[pages:read alpha:read alpha:write])
      expect(agent.reload.permissions).to eq(%w[pages:read alpha:read])
    end

    it "grants nothing when it's switched on again, so what someone took away stays away" do
      described_class.switch!(:alpha, on: true)
      editor.update!(permissions: %w[pages:read])
      described_class.switch!(:alpha, on: false)

      expect(described_class.switch!(:alpha, on: true)).to eq({})
      expect(editor.reload.permissions).to eq(%w[pages:read])
    end

    it "grants nothing for a plugin that starts on, whose defaults the roles were seeded with" do
      register :beta, enabled_by_default: true
      described_class.permissions :beta, "Beta", %w[beta:read], defaults: {editor: %w[beta:read]}

      expect(described_class.switch!(:beta, on: true)).to eq({})
      expect(editor.reload.permissions).to eq(%w[pages:read])
    ensure
      forget_plugin(:beta)
    end
  end

  describe "webhook event filters" do
    it "stores, validates and applies an event's criteria the way its plugin says" do
      register :alpha
      described_class.webhook_events :alpha, "Alpha", %w[alpha.happened]
      described_class.webhook_event_filter :alpha, "alpha.happened",
        permit: ->(raw) { raw.is_a?(Hash) || raw.is_a?(ActionController::Parameters) ? {"level" => raw["level"].to_s} : nil },
        validate: ->(value, errors) { errors.add(:event_filters, "level must be high or low") unless %w[high low].include?(value["level"]) },
        match: ->(value, payload) { value.nil? || value["level"] == payload[:level] }

      permitted = Webhook.permitted_event_filters(ActionController::Parameters.new("alpha.happened" => {"level" => "high", "x" => 1}, "other" => {}))
      expect(permitted).to eq("alpha.happened" => {"level" => "high"})

      webhook = Webhook.new(name: "a", url: "https://x.test/h", events: %w[alpha.happened], event_filters: {"alpha.happened" => {"level" => "mid"}})
      expect(webhook).not_to be_valid
      expect(webhook.errors[:event_filters]).to include("level must be high or low")

      webhook.event_filters = permitted
      expect(webhook.matches_filter?("alpha.happened", {level: "high"})).to be(true)
      expect(webhook.matches_filter?("alpha.happened", {level: "low"})).to be(false)
      expect(webhook.matches_filter?("page.published", {})).to be(true)
    end
  end

  describe "block type packs" do
    let(:pack) do
      [{slug: "alpha_hero", label: "Alpha hero", category: "sections", fields: []},
       {slug: "alpha_quote", label: "Alpha quote (plugin's)", category: "content", fields: []}]
    end

    before do
      register :alpha
      described_class.block_types :alpha, pack
    end

    it "installs a plugin's block types the first time it's switched on, never overwriting the site's" do
      BlockType.create!(slug: "alpha_quote", label: "Our own quote", category: "content", fields: [])

      described_class.switch!(:alpha, on: true)

      expect(BlockType.find_by(slug: "alpha_hero")).to be_present
      expect(BlockType.find_by(slug: "alpha_quote").label).to eq("Our own quote")
      expect(AuditLog.last).to have_attributes(action: "block_types.pack_installed")
      expect(AuditLog.last.metadata).to include("plugin" => "alpha", "slugs" => ["alpha_hero"])

      BlockType.find_by(slug: "alpha_hero").destroy!
      described_class.switch!(:alpha, on: false)
      described_class.switch!(:alpha, on: true)
      expect(BlockType.find_by(slug: "alpha_hero")).to be_nil, "only the first switch-on installs"
    end

    it "leaves a site with no block types for the starter pack, which includes the plugin's" do
      described_class.switch!(:alpha, on: true)

      expect(BlockType.count).to eq(0)
      expect(BlockType.starter_pack.map { it[:slug] }).to include("alpha_hero")
    end
  end
end
