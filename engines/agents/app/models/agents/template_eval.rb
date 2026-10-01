# frozen_string_literal: true

module Agents
  # A golden scenario for one shipped template: given this site, it must
  # recommend that.
  #
  # Evals live beside the templates they test because they are the same
  # artefact — a template is a claim about what an agent will do, and an eval
  # is the check on that claim.
  #
  # Two halves, split by what they cost:
  #
  #   validate  every eval names a real template and expects a recommendation
  #             kind that template's capabilities could actually produce.
  #             Free, and runs in CI on every commit.
  #   run       drive the real model against the fixture and score what came
  #             back. Costs money and needs a worker, so it is a task somebody
  #             chooses to run.
  #
  # The first half catches the mistakes people actually make: a capability
  # renamed and not updated in the four templates that grant it, an eval that
  # drifted from the template it names.
  class TemplateEval
    DIR = Agents::Engine.root.join("config/agents/evals")

    attr_reader :key, :template_key, :description, :fixture, :expect

    def self.all
      @all ||= Dir.glob(DIR.join("*.yml")).sort.filter_map { |path| load_file(path) }
    end

    def self.for_template(key) = all.select { |e| e.template_key == key.to_s }

    def self.reload!
      @all = nil
      all
    end

    def self.load_file(path)
      new(**YAML.safe_load_file(path).deep_symbolize_keys)
    rescue StandardError => e
      Rails.logger.warn("[Agents::TemplateEval] #{File.basename(path)}: #{e.class}: #{e.message}")
      nil
    end

    def initialize(key:, template:, expect:, fixture: {}, description: nil)
      @key = key.to_s
      @template_key = template.to_s
      @description = description.to_s.presence
      @fixture = (fixture || {}).deep_stringify_keys
      @expect = (expect || {}).symbolize_keys
    end

    def template = Agents::Registry.find(template_key)

    def recommends = Array(@expect[:recommends]).map(&:to_s)

    # …and none of these. The half that catches an agent wandering outside its
    # brief: a metadata pass that starts rewriting body copy has not failed
    # loudly, it has done something plausible and wrong.
    def never = Array(@expect[:never]).map(&:to_s)

    def min = (@expect[:min] || 1).to_i

    # Pure scoring, so the rules are testable without a model.
    def score(recommendations)
      kinds = Array(recommendations).map { |r| r.respond_to?(:kind) ? r.kind.to_s : r.to_s }
      missing = recommends.reject { |kind| kinds.count(kind) >= min }
      forbidden = never & kinds

      failures = []
      failures << "expected #{min}× #{missing.join(", ")}" if missing.any?
      failures << "must never recommend #{forbidden.join(", ")}" if forbidden.any?
      {passed: failures.empty?, failures: failures, kinds: kinds}
    end

    def errors
      messages = []
      messages << "key is blank" if key.blank?
      return messages + ["names no template"] if template_key.blank?

      shipped = template
      return messages + ["names template '#{template_key}', which is not in the library"] if shipped.nil?

      messages << "expects nothing, so it cannot fail" if recommends.empty? && never.empty?
      messages.concat(capability_errors(shipped))
      messages
    end

    def valid? = errors.empty?

    private

    # A template that cannot write, or cannot file a recommendation, cannot
    # produce one — an eval expecting it is testing a fiction.
    def capability_errors(shipped)
      return [] if recommends.empty?
      return [] if shipped.capabilities.include?("recommend")

      ["expects recommendations, but '#{shipped.key}' is not granted the `recommend` capability"]
    end
  end
end
