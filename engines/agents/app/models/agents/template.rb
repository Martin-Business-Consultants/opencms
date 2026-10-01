# frozen_string_literal: true

module Agents
  # One shipped agent blueprint: what it is for, how it works, what it may
  # use, and how much room it gets.
  #
  # Templates live in config/agents/*.yml rather than in a Ruby constant or a
  # database table, and that is the whole point of this class existing. A
  # template is behaviour, and behaviour belongs where it can be reviewed in a
  # pull request, versioned by git, and put through its evals in CI before it
  # reaches anybody. The previous arrangement — a Ruby array seeded into every
  # install — meant a fix to "Metadata Optimizer" was invisible to anyone
  # already running it.
  class Template
    TIERS = Ai::Models::TIERS

    ATTRS = %i[key version name description category icon tier cron budget capabilities
               instructions evals].freeze

    attr_reader(*ATTRS)

    def self.from_hash(hash)
      attrs = hash.to_h.deep_symbolize_keys
      new(**attrs.slice(*ATTRS))
    end

    def initialize(key:, name:, instructions:, version: 1, description: nil, category: nil,
                   icon: nil, tier: "mid", cron: nil, budget: nil, capabilities: [], evals: [])
      @key = key.to_s
      @version = version.to_i
      @name = name.to_s
      @description = description.to_s.presence
      @category = category.to_s.presence
      @icon = icon.presence || "sparkles"
      @tier = tier.to_s
      @cron = cron.to_s.presence
      @budget = Agents::Budget.from(budget)
      @capabilities = Array(capabilities).map(&:to_s)
      @evals = Array(evals).map(&:to_s)
      @instructions = instructions.to_s
    end

    def model = Ai::Models.for_tier(tier)

    # What a site's row looks like when it comes from this template. Used
    # both to seed the blueprint table and to show what an upgrade would
    # change on an agent already running it.
    # The subset an `Agent` actually has. A template carries a `category`,
    # which is how the catalogue groups it; an agent has no such column, and
    # handing it one is how "take the upgrade" turned into an
    # UnknownAttributeError instead of an upgrade.
    def to_agent_attributes
      to_record_attributes.except(:category)
    end

    def to_record_attributes
      {
        name: name,
        description: description,
        category: category,
        icon: icon,
        instructions: instructions,
        capability_keys: capabilities,
        preferred_model: tier,
        cron: cron
      }.compact
    end

    def to_h
      {key: key, version: version, name: name, description: description, category: category,
       icon: icon, tier: tier, cron: cron, budget: budget.to_h, capabilities: capabilities,
       evals: evals, instructions: instructions}
    end

    # --- validation --------------------------------------------------------
    #
    # Run in CI, never at request time: a template is a file in the repo, and a
    # broken one should fail a build rather than a site's agents page.
    def errors
      messages = []
      messages << "key is blank" if key.blank?
      messages << "key must be lower_snake_case" unless key.match?(/\A[a-z0-9_]+\z/)
      messages << "version must be 1 or more" if version < 1
      messages << "name is blank" if name.blank?
      messages << "instructions are blank" if instructions.blank?
      messages << "tier must be one of #{TIERS.join(", ")}" unless TIERS.include?(tier)
      messages << "no capabilities — an agent that may do nothing is not an agent" if capabilities.empty?

      unknown = capabilities - Agents::CapabilityCatalog.known.keys
      messages << "unknown capabilities: #{unknown.join(", ")}" if unknown.any?
      messages << "cron '#{cron}' does not parse" if cron.present? && Fugit.parse_cron(cron).nil?
      messages
    end

    def valid? = errors.empty?
  end
end
