# frozen_string_literal: true

module Ai
  # Which model a piece of work runs on, named by what the work needs rather
  # than by a model id.
  #
  # Agents and swarm seats used to carry `preferred_model: "opus"` — a string
  # that meant something on the day it was typed and silently meant nothing
  # after the provider changed. A tier survives that: it says "this job needs
  # judgement" or "this job is mechanical", and the mapping to a model is one
  # table, in one file, that a person can be shown.
  #
  # The list is deliberately short. An id that isn't here can't be stored
  # against an agent, so a typo in a form can't produce runs nobody can
  # explain — and Settings carries one escape hatch for trying a new id before
  # it earns a place here.
  module Models
    ZEN = {
      "deepseek-v4-flash" => {
        name: "DeepSeek V4 Flash",
        tier: "cheap",
        note: "Mechanical work — extraction, rewriting, short structured answers."
      },
      "glm-5.3" => {
        name: "GLM 5.3",
        tier: "mid",
        note: "The everyday default. Reads a lot of content and holds it together."
      },
      "kimi-k3" => {
        name: "Kimi K3",
        tier: "strong",
        note: "Judgement and prose — audits, strategy, anything a person will read verbatim."
      }
    }.freeze

    TIERS = %w[cheap mid strong].freeze

    BY_TIER = ZEN.each_with_object({}) { |(id, spec), acc| acc[spec[:tier]] = id }.freeze

    DEFAULT_TIER = "mid"

    module_function

    def all = ZEN

    # The site's saved default, falling back to ours.
    def default_tier
      tier = Setting.get("ai")["default_tier"].to_s
      TIERS.include?(tier) ? tier : DEFAULT_TIER
    rescue StandardError
      DEFAULT_TIER
    end

    # One extra Zen id typed into Settings — for running a model that has just
    # landed, before it is worth a deploy. Blank is the norm.
    def extra_model
      Setting.get("ai")["extra_model"].presence
    rescue StandardError
      nil
    end

    def known?(model)
      id = model.to_s
      ZEN.key?(id) || (id.present? && id == extra_model)
    end

    def for_tier(tier)
      BY_TIER[tier.to_s] || BY_TIER[default_tier] || ZEN.keys.first
    end

    # Resolve whatever an agent stored — a tier, a model id, or nothing — to a
    # model id. Accepting both is what lets tiers arrive without a migration
    # that rewrites every row, and without a stored id becoming a broken run.
    def resolve(preference = nil)
      value = preference.to_s
      return for_tier(value) if TIERS.include?(value)
      return value if known?(value)

      for_tier(default_tier)
    end

    def tier_of(preference)
      value = preference.to_s
      return value if TIERS.include?(value)

      ZEN.dig(value, :tier) || default_tier
    end

    def label(model)
      id = resolve(model)
      ZEN.dig(id, :name) || id
    end

    # What a picker offers: the three tiers, named by what they are for, plus
    # any id already stored that is not one of them — because dropping a
    # stored value the moment someone opens a form is a change nobody made.
    def tier_options
      TIERS.map do |tier|
        id = for_tier(tier)
        {value: tier, label: "#{tier.capitalize} — #{ZEN.dig(id, :name) || id}", hint: ZEN.dig(id, :note)}
      end
    end

    def options_including(current)
      options = tier_options
      value = current.to_s
      return options if value.blank? || TIERS.include?(value)

      options + [{value: value, label: "#{label(value)} (pinned model)", hint: "Stored before tiers; still runnable."}]
    end
  end
end
