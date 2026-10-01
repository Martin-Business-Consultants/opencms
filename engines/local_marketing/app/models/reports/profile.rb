# frozen_string_literal: true

# What the reports are ABOUT: one local business, in one place.
#
# Every DataForSEO call needs some subset of the same handful of facts — the
# domain, where the business physically is, what it's called on Google, and
# which queries matter to it. Held together here rather than passed around as
# a bag of strings, so a report can say "I can't run, I need a place_id"
# instead of returning an empty result that looks like bad news about the
# business.
#
# Read from Settings → Reporting. `site_base_url` is borrowed from Settings →
# General rather than duplicated: the domain being reported on is the domain
# being published, and two fields that must agree eventually won't.
module Reports
  class Profile
    SETTING_KEY = "reporting"

    # DataForSEO's own default — the United States. Stated rather than left
    # implicit because a local report that silently ranks a Cardiff business
    # against US results is wrong in a way that looks plausible.
    DEFAULT_LOCATION_CODE = 2840
    DEFAULT_LANGUAGE_CODE = "en"

    # Stored as arrays, entered as textareas.
    LIST_FIELDS = %w[brand_terms tracked_keywords competitors audit_urls map_keywords citation_directories].freeze
    CREDENTIALS = %w[dataforseo_login dataforseo_password].freeze

    def self.load
      new(Setting.get(SETTING_KEY), Setting.get("general"))
    end

    # Saves what Settings › Reporting posted. A blank credential field means
    # "leave the saved one alone" — the normal state of a password input
    # that never receives its own value back — and both halves of the
    # credential go to the encrypted column, the login included: it is half
    # of a secret, not a username.
    def self.change(attributes)
      incoming = attributes.to_h.stringify_keys
      credentials = incoming.slice(*CREDENTIALS).select { |_, v| v.to_s.strip.present? }
      Setting.set_secret(SETTING_KEY, credentials) if credentials.any?
      incoming.except!(*CREDENTIALS)

      LIST_FIELDS.each do |field|
        incoming[field] = split_list(incoming[field]) if incoming.key?(field)
      end
      incoming["location_code"] = incoming["location_code"].to_i if incoming["location_code"].present?
      incoming["map_grid_size"] = incoming["map_grid_size"].to_i if incoming.key?("map_grid_size")
      incoming["map_spacing_km"] = incoming["map_spacing_km"].to_f if incoming.key?("map_spacing_km")
      incoming["sandbox"] = ActiveModel::Type::Boolean.new.cast(incoming["sandbox"]) if incoming.key?("sandbox")

      Setting.set(SETTING_KEY, incoming)
      Event.record("settings.reporting_updated", credentials_changed: credentials.any?)
    end

    def self.split_list(value)
      items = value.is_a?(Array) ? value : value.to_s.split(/[\r\n,]+/)
      items.map { |item| item.to_s.strip }.reject(&:blank?).uniq
    end

    def initialize(data, general = {})
      @data = (data || {}).with_indifferent_access
      @general = (general || {}).with_indifferent_access
    end

    # The business as Google knows it.
    def business_name = @data[:business_name].to_s.strip
    def place_id      = @data[:place_id].to_s.strip
    def cid           = @data[:cid].to_s.strip

    # Where it is. `location_name` wins when both are set: it is the one a
    # human typed and can check, and DataForSEO resolves it to the same code.
    def location_name = @data[:location_name].to_s.strip
    def location_code = (@data[:location_code].presence || DEFAULT_LOCATION_CODE).to_i

    # The code only if somebody actually set one.
    #
    # `location_code` above defaults to 2840 so a city-scoped request always
    # has something to send. That default must not leak into country
    # resolution: "unset" would match United States and quietly outrank the
    # real country every time.
    def configured_location_code = @data[:location_code].presence&.to_i
    def language_code = (@data[:language_code].presence || DEFAULT_LANGUAGE_CODE).to_s

    # The country, on its own.
    #
    # The SERP and Business Data endpoints want the city — that is the point
    # of a local report. The AI Optimization endpoints only index by country
    # and reject a city with `40501 Invalid Field: 'location_name'`, so they
    # need this instead. See DataForSeo::Locations.
    #
    # DataForSEO writes a location as "City,Region,Country", so the last
    # segment is the country; an explicit setting overrides that for the
    # cases where it isn't.
    def country_name
      explicit = @data[:country_name].to_s.strip
      return explicit if explicit.present?

      location_name.split(",").last.to_s.strip
    end

    # Brand terms to watch in LLM answers — the business name plus whatever
    # else it gets called. Distinct from tracked_keywords, which are the
    # queries customers type.
    def brand_terms      = list(:brand_terms).presence || [business_name].reject(&:blank?)
    def tracked_keywords = list(:tracked_keywords)
    def competitors      = list(:competitors)

    # The site itself. Bare host, no scheme or www — the form every
    # DataForSEO `target` field wants.
    def domain
      raw = @data[:domain].presence || @general[:site_base_url]
      host = raw.to_s.strip
      host = URI.parse(host).host.to_s if host.start_with?("http")
      host.sub(/\Awww\./, "").sub(%r{/.*\z}, "").presence.to_s
    rescue URI::InvalidURIError
      ""
    end

    def base_url
      url = @general[:site_base_url].to_s.strip
      return url.chomp("/") if url.start_with?("http")
      return "https://#{domain}" if domain.present?

      ""
    end

    # The rank map: an n×n grid of points around the business, `spacing`
    # kilometres apart, each asked the same Maps query. Odd sizes so the
    # business sits on the centre point. Every cell is one paid call per
    # keyword, so the keyword list for the map is its own, short by default.
    MAP_GRID_SIZES = [3, 5, 7].freeze
    DEFAULT_MAP_GRID_SIZE = 5
    DEFAULT_MAP_SPACING_KM = 1.5
    DEFAULT_MAP_KEYWORDS = 3

    def map_grid_size
      size = @data[:map_grid_size].to_i
      MAP_GRID_SIZES.include?(size) ? size : DEFAULT_MAP_GRID_SIZE
    end

    def map_spacing_km
      km = @data[:map_spacing_km].to_f
      km.between?(0.25, 25) ? km : DEFAULT_MAP_SPACING_KM
    end

    def map_keywords
      list(:map_keywords).presence || tracked_keywords.first(DEFAULT_MAP_KEYWORDS)
    end

    # The NAP — name, address, phone — as the business wants it written
    # everywhere. Citations are checked against this. Blank here falls back
    # to what Google holds (the latest Business profile snapshot), because
    # Google's version is the one every other directory is compared to.
    def phone = @data[:phone].to_s.strip
    def address = @data[:address].to_s.strip

    # Directories to audit for citations, as bare domains. The default is the
    # set that matters for a US business; every trade has verticals worth
    # adding. Two of the defaults can't be searched (Apple Maps and Bing
    # Places don't expose listings to Google) and are managed by hand.
    US_CITATION_DIRECTORIES = %w[
      yelp.com bbb.org yellowpages.com foursquare.com facebook.com
      mapquest.com superpages.com manta.com bingplaces.com maps.apple.com
    ].freeze

    def citation_directories
      list(:citation_directories).map { |d| d.downcase.sub(%r{\Ahttps?://}, "").sub(/\Awww\./, "").sub(%r{/.*}, "") }
                                 .reject(&:blank?).presence || US_CITATION_DIRECTORIES
    end

    # Pages worth auditing. Defaults to the home page, because a site-health
    # report that needs configuration before it says anything gets skipped.
    def audit_urls
      urls = list(:audit_urls)
      return urls if urls.any?

      base_url.present? ? [base_url] : []
    end

    # The location half of a request body, in the shape DataForSEO expects.
    def location_params
      location_name.present? ? {location_name: location_name} : {location_code: location_code}
    end

    def configured? = domain.present? || business_name.present?

    # Which of the above a given report is missing. Reports declare what they
    # need; the UI uses this to disable a card with a reason on it rather
    # than letting someone spend money on a call that can't succeed.
    def missing(requirements)
      Array(requirements).reject { |field| public_send(field).presence }
    end

    def to_h
      {
        business_name: business_name, place_id: place_id, cid: cid,
        location_name: location_name, location_code: location_code,
        country_name: country_name,
        language_code: language_code, domain: domain, base_url: base_url,
        brand_terms: brand_terms, tracked_keywords: tracked_keywords,
        competitors: competitors, audit_urls: audit_urls,
        map_grid_size: map_grid_size, map_spacing_km: map_spacing_km, map_keywords: map_keywords,
        phone: phone, address: address, citation_directories: citation_directories
      }
    end

    private

    # Stored as an array, but a textarea sends a string. Accept both so the
    # settings form and the API can't drift into different shapes.
    def list(key) = self.class.split_list(@data[key])
  end
end
