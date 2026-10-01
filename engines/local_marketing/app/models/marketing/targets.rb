# frozen_string_literal: true

module Marketing
  # What "good" means for this business — the numbers the scorecard measures
  # against.
  #
  # A business template supplies defaults; the business owns the values. They
  # live in `Setting["marketing"]["targets"]` and every key falls back to the
  # template's default, then to a conservative one here, so a scorecard can
  # always be computed — a missing target is a shrug, not a crash.
  module Targets
    SETTING_KEY = "marketing"

    # key => [label, direction, fallback]. Direction says which way is good.
    DEFINITIONS = {
      "top_3"                  => ["Keywords in the top 3", :up, 15],
      "keywords_ranked"        => ["Keywords ranked", :up, 250],
      "map_pack_share"         => ["Map-pack share (%)", :up, 60],
      "citations_consistent"   => ["Consistent citations", :up, 8],
      "rating"                 => ["Google rating", :up, 4.6],
      "reviews"                => ["Google reviews", :up, 75],
      "positive_mentions"      => ["Positive web mentions (%)", :up, 65],
      "ai_mention_rate"        => ["AI answers naming us (%)", :up, 25],
      "ai_mentions"            => ["AI mentions", :up, 20],
      "page_score"             => ["On-page score", :up, 85],
      "lighthouse_performance" => ["Lighthouse performance", :up, 70]
    }.freeze

    module_function

    def all(template = nil)
      stored = (Setting.get(SETTING_KEY)["targets"] || {}).to_h
      template_defaults = template&.targets || {}
      DEFINITIONS.to_h do |key, (_label, _dir, fallback)|
        value = stored[key].presence || template_defaults[key].presence || fallback
        [key, value.to_f]
      end
    end

    def label(key) = DEFINITIONS.dig(key.to_s, 0)
    def direction(key) = DEFINITIONS.dig(key.to_s, 1)

    def save(values)
      clean = values.to_h.slice(*DEFINITIONS.keys).transform_values { |v| v.to_f }.reject { |_, v| v.zero? }
      Setting.set(SETTING_KEY, "targets" => clean)
    end
  end
end
