# frozen_string_literal: true

# Registry of report definitions. Frozen list, same reasoning as
# RecurringTasks::Catalog — definitions are Ruby classes, so adding one is a
# code change and the UI can be sourced entirely from here.
#
# Order is the order the index renders them, and it is deliberate: the
# question people ask first is "are we visible", then "what do we rank for",
# then "is the listing right", then "what do people say", then "is the site
# broken". Within a group, the report to run first comes first.
module Reports
  module Catalog
    DEFINITIONS = [
      # AI visibility — do the assistants know we exist?
      Definitions::LlmVisibility,
      Definitions::AiAnswers,
      Definitions::AiKeywordDemand,
      # Search — what do we rank for, what could we, and who else does?
      Definitions::RankedKeywords,
      Definitions::VisibilityHistory,
      Definitions::KeywordDemand,
      Definitions::KeywordOpportunities,
      Definitions::Competitors,
      Definitions::SearchTrends,
      # Local — the map pack, Maps itself, the listing, and the field around it.
      Definitions::LocalRankings,
      Definitions::MapsRankings,
      Definitions::RankMap,
      Definitions::BusinessProfile,
      Definitions::LocalCompetitors,
      Definitions::Citations,
      # Reputation — what people say.
      Definitions::GoogleReviews,
      Definitions::WebMentions,
      # Authority — what other sites confer.
      Definitions::Backlinks,
      # Site health — is the site itself in order? The audit first: it is
      # the one that says what's wrong in words, with the fix beside it.
      Definitions::SiteAudit,
      Definitions::PageHealth,
      Definitions::Lighthouse
    ].freeze

    BY_KEY = DEFINITIONS.index_by(&:key).freeze
    KEYS   = BY_KEY.keys.freeze

    module_function

    # The core's reports and those enabled plugins add
    # (Cms::Plugins.report_definition).
    def all = DEFINITIONS + Cms::Plugins.enabled_report_definitions.values

    def keys = all.map(&:key)

    def known?(key) = !definition_class(key).nil?

    def definition_class(key) = BY_KEY[key.to_s] || Cms::Plugins.enabled_report_definitions[key.to_s]

    def fetch(key, profile:, client:)
      klass = definition_class(key)
      raise ArgumentError, "unknown report #{key.inspect}" unless klass

      klass.new(profile: profile, client: client)
    end

    # Groups, in catalog order, for the index page.
    def groups
      all.group_by(&:group)
    end
  end
end
