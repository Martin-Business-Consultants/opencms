# frozen_string_literal: true

module Reports
  module Definitions
    # Ask the assistants the questions customers ask, and read who they name.
    #
    # LLM Mentions (AI visibility) reads a corpus of past answers. This asks
    # for fresh ones: each tracked keyword goes to ChatGPT and Gemini as a
    # prompt, with web search on and the business's own city as the search
    # location, and the answer is read for the brand, the domain, the
    # configured competitors and every source it cites. It is the most direct
    # measurement of AI visibility there is — and the most expensive per
    # question, which is why the prompt count is capped low.
    class AiAnswers < Definition
      # `geo:` — whether the endpoint takes the web-search location fields.
      # ChatGPT's does; Gemini's rejects them with 40501 despite the family
      # resemblance, so Gemini is told where the user is in the system
      # message instead. Same question, two ways of asking it locally.
      PLATFORMS = {
        "chat_gpt" => {path: "ai_optimization/chat_gpt/llm_responses/live", model: "gpt-4o-mini",      geo: true},
        "gemini"   => {path: "ai_optimization/gemini/llm_responses/live",   model: "gemini-2.5-flash", geo: false}
      }.freeze

      MAX_PROMPTS = 5
      EXCERPT = 320

      def self.title = "AI answers"

      def self.description
        "Asks ChatGPT and Gemini the tracked queries, from the business's own " \
        "city, and reads each answer for the brand, the competitors and the sources it cites."
      end

      def self.group = "AI visibility"
      def self.requires = [:tracked_keywords, :brand_terms]
      def self.estimated_cost = 0.15
      def self.cadence = "weekly"
      def self.location_granularity = :country
      def self.locations_api = "dataforseo_labs"

      def self.trend_metrics
        [
          {key: "mention_rate", label: "Mentioned (%)", good: "up"},
          {key: "mentioned_in", label: "Answers naming us", good: "up"},
          {key: "answers", label: "Answers", good: nil},
          {key: "competitor_mentions", label: "Competitor mentions", good: "down"}
        ]
      end

      def self.trend_point(data)
        {
          "mention_rate" => data["mention_rate"]&.to_f,
          "mentioned_in" => data["mentioned_in"].to_i,
          "answers" => data["answers"].to_i,
          "competitor_mentions" => Array(data["competitors_mentioned"]).sum { |c| c["count"].to_i }
        }
      end

      def call
        prompts = profile.tracked_keywords.first(MAX_PROMPTS)
        iso = DataForSeo::Locations.new(client, api: "dataforseo_labs")
                                   .country_iso(country_name: profile.country_name,
                                                location_code: profile.configured_location_code)
        city = profile.location_name.split(",").first.to_s.strip

        rows = prompts.flat_map do |prompt|
          PLATFORMS.map { |platform, spec| answer(platform, spec, prompt, iso, city) }
        end
        answered = rows.reject { |row| row[:error] }

        locale_data.merge(
          prompts: prompts,
          city: city,
          answers: answered.length,
          mentioned_in: answered.count { |row| row[:mentioned] },
          mention_rate: answered.empty? ? nil : ((answered.count { |r| r[:mentioned] } / answered.length.to_f) * 100).round,
          by_platform: PLATFORMS.keys.map do |platform|
            mine = answered.select { |row| row[:platform] == platform }
            {platform: platform, answers: mine.length, mentioned: mine.count { |r| r[:mentioned] }}
          end,
          cited_domains: tally(answered.flat_map { |row| row[:cited_domains] }),
          competitors_mentioned: tally(answered.flat_map { |row| row[:competitors] }),
          rows: rows
        )
      end

      private

      def answer(platform, spec, prompt, iso, city)
        where = [city.presence, profile.country_name.presence].compact.join(", ")
        task = {
          user_prompt: prompt,
          model_name: spec[:model],
          web_search: true,
          max_output_tokens: 1024,
          system_message: system_message(where, geo: spec[:geo])
        }
        if spec[:geo]
          task[:web_search_country_iso_code] = iso.presence
          task[:web_search_city] = city.presence
        end
        response = fetch(spec[:path], task)
        result = response.first || {}
        text = text_of(result)
        urls = urls_of(result)
        cited = urls.map { |url| host(url) }.compact.uniq

        {
          platform: platform,
          model: result["model_name"].to_s,
          prompt: prompt,
          mentioned: mentions_us?(text, cited),
          competitors: profile.competitors.select { |c| mentions_domain?(c, text, cited) },
          cited_domains: cited,
          excerpt: text.to_s.strip.truncate(EXCERPT),
          cost: response.cost
        }
      rescue DataForSeo::Error => e
        {platform: platform, prompt: prompt, error: e.message.truncate(200), mentioned: false, competitors: [], cited_domains: []}
      end

      # Kept under the endpoint's 500-character limit. When the endpoint has
      # no location fields the location goes here, which is how a person
      # would ask anyway.
      def system_message(where, geo:)
        base = "The user is a customer looking for a local business. Recommend specific named businesses where you can."
        return base if geo || where.blank?

        "#{base} The user is in #{where}."
      end

      def text_of(result)
        Array(result["items"])
          .select { |item| item["type"] == "message" }
          .flat_map { |item| Array(item["sections"]) }
          .map { |section| section["text"].to_s }
          .join("\n")
      end

      def urls_of(result)
        Array(result["items"])
          .flat_map { |item| Array(item["sections"]) }
          .flat_map { |section| Array(section["annotations"]) }
          .map { |a| a["url"].to_s }
          .reject(&:blank?)
      end

      def mentions_us?(text, cited)
        down = text.downcase
        return true if profile.brand_terms.any? { |term| down.include?(term.downcase) }

        mentions_domain?(profile.domain, text, cited)
      end

      def mentions_domain?(domain, text, cited)
        return false if domain.blank?

        bare = domain.downcase.sub(/\Awww\./, "")
        cited.any? { |h| h == bare || h.end_with?(".#{bare}") } || text.downcase.include?(bare)
      end

      def host(url)
        URI.parse(url).host&.downcase&.sub(/\Awww\./, "")
      rescue URI::InvalidURIError
        nil
      end

      def tally(values)
        values.compact.group_by(&:itself).map { |key, v| {key: key, count: v.length} }
              .sort_by { |row| -row[:count] }.first(20)
      end
    end
  end
end
