# frozen_string_literal: true

module Marketing
  # One business type, from config/businesses/*.yml: what a marketer would
  # otherwise set up by hand for a dentist, a storage facility, a plumber.
  #
  # The insight is that these are the same product with different defaults,
  # and that nearly every default is derivable from type + city. So the
  # template supplies patterns and lists; `defaults_for(city:)` turns them
  # into the concrete keywords, directories and settings a business needs.
  class BusinessTemplate
    ATTRS = %i[key version name description category schema_type footprint services
               keyword_patterns modifiers directories reports agents targets content_scaffold].freeze
    attr_reader(*ATTRS)

    FOOTPRINTS = %w[storefront service_area].freeze
    MAP_DEFAULTS = {
      "storefront" => {grid: 5, spacing_km: 1.5},
      "service_area" => {grid: 7, spacing_km: 3.0}
    }.freeze

    def self.from_hash(hash)
      h = hash.deep_symbolize_keys
      new(**h.slice(*ATTRS))
    end

    def initialize(key:, name:, version: 1, description: nil, category: nil, schema_type: "LocalBusiness",
                   footprint: "storefront", services: [], keyword_patterns: [], modifiers: [], directories: [],
                   reports: [], agents: [], targets: {}, content_scaffold: [])
      @key = key.to_s
      @version = version.to_i
      @name = name.to_s
      @description = description.to_s
      @category = category.to_s
      @schema_type = schema_type.to_s
      @footprint = footprint.to_s
      @services = Array(services).map(&:to_s)
      @keyword_patterns = Array(keyword_patterns).map(&:to_s)
      @modifiers = Array(modifiers).map(&:to_s)
      @directories = Array(directories).map(&:to_s)
      @reports = Array(reports).map { |r| r.is_a?(Hash) ? r.transform_keys(&:to_s) : {"kind" => r.to_s} }
      @agents = Array(agents).map(&:to_s)
      @targets = (targets || {}).transform_keys(&:to_s)
      @content_scaffold = Array(content_scaffold).map { |c| c.transform_keys(&:to_s) }
    end

    def report_kinds = @reports.map { |r| r["kind"] }
    def cadence_for(kind) = @reports.find { |r| r["kind"] == kind }&.dig("cadence")

    # The concrete setup for a city. Patterns take {service}, {city} and
    # {modifier}; a pattern without {modifier} is expanded once per service,
    # one with it once per service × modifier — so "cheap {service} {city}"
    # doesn't multiply into a hundred keywords.
    def defaults_for(city:)
      city = city.to_s.strip
      keywords = []
      @keyword_patterns.each do |pattern|
        @services.each do |service|
          if pattern.include?("{modifier}")
            @modifiers.each { |m| keywords << fill(pattern, service, city, m) }
          else
            keywords << fill(pattern, service, city)
          end
        end
      end
      keywords = keywords.map { |k| k.squeeze(" ").strip }.reject(&:blank?).uniq

      {
        keywords: keywords.first(40),
        map_keywords: keywords.first(3),
        brand_terms: [],
        directories: (Reports::Profile::US_CITATION_DIRECTORIES + @directories).uniq,
        map_grid_size: MAP_DEFAULTS.fetch(@footprint, MAP_DEFAULTS["storefront"])[:grid],
        map_spacing_km: MAP_DEFAULTS.fetch(@footprint, MAP_DEFAULTS["storefront"])[:spacing_km],
        targets: Targets::DEFINITIONS.to_h { |k, (_l, _d, fb)| [k, (@targets[k] || fb).to_f] },
        reports: @reports,
        agents: @agents,
        schema_type: @schema_type,
        category: @category
      }
    end

    # Roughly what one full baseline costs, from the catalog's estimates.
    def baseline_cost
      report_kinds.sum { |k| Reports::Catalog.definition_class(k)&.estimated_cost.to_f }.round(2)
    end

    def problems
      out = []
      out << "name is blank" if @name.blank?
      out << "footprint must be one of #{FOOTPRINTS.join(", ")}" unless FOOTPRINTS.include?(@footprint)
      out << "has no services" if @services.empty?
      out << "has no keyword patterns" if @keyword_patterns.empty?
      out << "patterns must mention {service}: #{@keyword_patterns.reject { |p| p.include?("{service}") }.join(", ")}" if @keyword_patterns.any? { |p| !p.include?("{service}") }
      unknown_reports = report_kinds - Reports::Catalog::KEYS
      out << "unknown reports: #{unknown_reports.join(", ")}" if unknown_reports.any?
      # Checked against the Agents plugin's library while it's on.
      if (agents = Cms::Plugins.provided(:agents))
        unknown_agents = @agents - agents.library_keys
        out << "unknown agents: #{unknown_agents.join(", ")}" if unknown_agents.any?
      end
      unknown_targets = @targets.keys - Targets::DEFINITIONS.keys
      out << "unknown targets: #{unknown_targets.join(", ")}" if unknown_targets.any?
      out
    end

    private

    def fill(pattern, service, city, modifier = nil)
      pattern.gsub("{service}", service).gsub("{city}", city).gsub("{modifier}", modifier.to_s)
    end
  end
end
