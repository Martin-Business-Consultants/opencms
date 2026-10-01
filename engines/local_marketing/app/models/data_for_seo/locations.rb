# frozen_string_literal: true

module DataForSeo
  # Resolves the profile's location to a `location_code` an endpoint will
  # accept — and never sends a name.
  #
  # Three endpoints in a row rejected `location_name` with
  #
  #   40501 Invalid Field: 'location_name'
  #
  # despite each one's documentation listing the field. Whatever the cause
  # (a value that doesn't match the API's spelling to the character, a live
  # method stricter than its docs), the fix is the same and it is structural:
  # look the location up in the API's OWN list and send the code. Codes are
  # unambiguous; names are a negotiation.
  #
  # Two scopes, because "location" is not one thing across DataForSEO:
  #
  #   :country  Labs, LLM Mentions, AI Keyword Data — indexed by country,
  #             ~90 rows per list, no cities anywhere
  #   :city     SERP, Business Data — ~100k rows in total, so fetched per
  #             country via `/locations/{iso}` (a few thousand rows, free)
  #
  # Every list is fetched from the API rather than hard-coded: they are
  # per-API, they differ, and a stale table here would fail the same way with
  # a different cause. They are reference data, so they are cached hard.
  class Locations
    APIS = {
      "dataforseo_labs"      => {path: "dataforseo_labs/locations_and_languages",                 scope: :country},
      "llm_mentions"         => {path: "ai_optimization/llm_mentions/locations_and_languages",    scope: :country},
      "ai_keyword_data"      => {path: "ai_optimization/ai_keyword_data/locations_and_languages", scope: :country},
      "serp_google"          => {path: "serp/google/locations/%<iso>s",                            scope: :city},
      "business_data_google" => {path: "business_data/google/locations/%<iso>s",                   scope: :city}
    }.freeze

    # DataForSEO's own default, and the only location ChatGPT data covers.
    DEFAULT_CODE = 2840
    DEFAULT_NAME = "United States"
    DEFAULT_LANGUAGE = "en"

    CACHE_TTL = 7.days

    # Why the answer is what it is. The causes have different fixes, and a
    # message that names the wrong one sends someone to repair something
    # that isn't broken.
    REASONS = %i[exact configured no_country unsupported lookup_failed].freeze

    Resolved = Struct.new(:location_code, :location_name, :language_code, :reason, :requested, keyword_init: true) do
      def exact? = %i[exact configured].include?(reason)
      def fallback? = !exact?
    end

    def initialize(client, api:)
      @client = client
      @api = api.to_s
      raise ArgumentError, "unknown locations API #{api.inspect}" unless APIS.key?(@api)
    end

    def scope = APIS.fetch(@api)[:scope]

    # ---- country ----------------------------------------------------------

    # Country name (or an explicitly-set code) → the code a country-scoped
    # API accepts. Falls back to the default rather than raising, with the
    # reason attached, because a country report against the United States
    # that says so is still useful; the caller surfaces `fallback?`.
    def resolve(country_name: nil, location_code: nil, language_code: nil)
      language = language_code.presence || DEFAULT_LANGUAGE
      requested = country_name.presence || location_code

      rows = all
      return fallback(:lookup_failed, language, requested) if rows.nil?

      match = find_by_name(rows, country_name) || find_by_code(rows, location_code)
      return fallback(requested.present? ? :unsupported : :no_country, language, requested) unless match

      Resolved.new(
        location_code: match["location_code"].to_i,
        location_name: match["location_name"].to_s,
        language_code: language_for(match, language),
        reason: :exact,
        requested: requested
      )
    end

    # The two-letter ISO code for a country, from a country-scoped list —
    # the key the city lists are filed under. Nil when it can't be known.
    def country_iso(country_name: nil, location_code: nil)
      rows = all
      return nil if rows.nil?

      match = find_by_name(rows, country_name) || find_by_code(rows, location_code)
      match&.dig("country_iso_code").presence
    end

    # ---- city -------------------------------------------------------------

    # "Cardiff,Wales,United Kingdom" → the code for that city in THIS API's
    # list for that country.
    #
    # A code the user set explicitly is trusted as-is: a code is already the
    # thing we are trying to arrive at, and the API will say if it is wrong.
    # Otherwise the name is matched to the character (after normalising the
    # spaces people type after commas), then by its first segment — the city
    # — because "Cardiff" is what someone writes and
    # "Cardiff,Wales,United Kingdom" is what the list says.
    def resolve_city(location_name: nil, location_code: nil, iso: nil, language_code: nil)
      language = language_code.presence || DEFAULT_LANGUAGE
      requested = location_name.presence || location_code

      if location_code.present? && location_code.to_i.positive?
        return Resolved.new(location_code: location_code.to_i, location_name: location_name.presence || location_code.to_s,
                            language_code: language, reason: :configured, requested: requested)
      end

      return fallback(:no_country, language, requested) if iso.blank? || location_name.blank?

      rows = all(iso: iso)
      return fallback(:lookup_failed, language, requested) if rows.nil?

      match = find_by_name(rows, location_name) || find_by_city(rows, location_name)
      return fallback(:unsupported, language, requested) unless match

      Resolved.new(
        location_code: match["location_code"].to_i,
        location_name: match["location_name"].to_s,
        language_code: language,
        reason: :exact,
        requested: requested
      )
    end

    # ---- the lists --------------------------------------------------------

    # The supported list, or **nil** when it could not be read. nil rather
    # than [] on purpose: "nothing is supported" and "I could not find out"
    # are different answers, and only one of them is ever true.
    def all(iso: nil)
      path = format(APIS.fetch(@api)[:path], iso: iso.to_s.downcase)
      Rails.cache.fetch("dataforseo:locations:#{@api}:#{iso.to_s.downcase}", expires_in: CACHE_TTL) do
        @client.get(path)
      end
    rescue StandardError => e
      Rails.logger.warn("[DataForSeo::Locations] #{@api}#{iso && "/#{iso}"} lookup failed: #{e.class}: #{e.message}")
      nil
    end

    def supports?(country_name)
      rows = all
      return nil if rows.nil?

      find_by_name(rows, country_name).present?
    end

    private

    def find_by_code(rows, code)
      return nil if code.blank? || code.to_i.zero?

      rows.find { |row| row["location_code"].to_i == code.to_i }
    end

    def find_by_name(rows, name)
      return nil if name.blank?

      wanted = normalize(name)
      rows.find { |row| normalize(row["location_name"]) == wanted }
    end

    # First segment only, among rows that ARE cities. Prefer the one whose
    # full name the user's value is a prefix of — "Cardiff,Wales" narrows
    # two Cardiffs to one.
    def find_by_city(rows, name)
      city = normalize(name).split(",").first.to_s
      return nil if city.blank?

      candidates = rows.select do |row|
        row["location_type"].to_s.casecmp?("City") && normalize(row["location_name"]).start_with?("#{city},")
      end
      return nil if candidates.empty?

      wanted = normalize(name)
      candidates.find { |row| normalize(row["location_name"]).start_with?(wanted) } || candidates.first
    end

    # Countries whose common name isn't the one DataForSEO lists, plus the
    # constituent nations of the UK — a business in Cardiff writes "Wales",
    # and no list of countries contains it.
    ALIASES = {
      "usa" => "united states", "us" => "united states", "u.s." => "united states",
      "u.s.a." => "united states", "united states of america" => "united states",
      "uk" => "united kingdom", "u.k." => "united kingdom",
      "great britain" => "united kingdom", "britain" => "united kingdom",
      "england" => "united kingdom", "scotland" => "united kingdom",
      "wales" => "united kingdom", "northern ireland" => "united kingdom",
      "eire" => "ireland", "republic of ireland" => "ireland",
      "holland" => "netherlands", "uae" => "united arab emirates"
    }.freeze

    # Case-insensitive, and forgiving of the spaces people type after commas.
    # "Cardiff, Wales, United Kingdom" and "Cardiff,Wales,United Kingdom" are
    # the same place; only one of them matches DataForSEO to the character.
    def normalize(value)
      key = value.to_s.split(",").map { |part| part.strip.downcase }.reject(&:empty?).join(",")
      ALIASES.fetch(key, key)
    end

    def language_for(row, wanted)
      available = Array(row["available_languages"]).map { |l| l["language_code"].to_s }
      return wanted if available.empty? || available.include?(wanted)

      available.include?(DEFAULT_LANGUAGE) ? DEFAULT_LANGUAGE : available.first
    end

    def fallback(reason, language, requested)
      Resolved.new(location_code: DEFAULT_CODE, location_name: DEFAULT_NAME, language_code: language,
                   reason: reason, requested: requested)
    end
  end
end
