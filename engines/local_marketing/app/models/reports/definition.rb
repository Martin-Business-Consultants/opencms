# frozen_string_literal: true

# Base class for a report: one DataForSEO question, asked and normalized.
#
# A definition owns three things — what it needs from the Profile before it
# can run, how to ask DataForSEO, and how to reduce the answer to something
# a person can read. That last part is the whole point. DataForSEO responses
# are large and mostly irrelevant; storing them whole gives you a database
# full of JSON nobody opens. Each report keeps the handful of numbers that
# answer its question and throws the rest away.
#
# Subclasses implement `call` and return a Hash, which is stored verbatim as
# `Report#data`, rendered by the report page and returned by /api/reports. Keep it flat, keep it
# small, and give every number a name a client would recognise.
module Reports
  class Definition
    class << self
      def key = name.demodulize.underscore

      def title       = ""
      def description = ""

      # Sidebar/section grouping on the index.
      def group = "Search"

      # Profile fields that must be present. See Profile#missing.
      def requires = []

      # Roughly what one run costs, in USD, for the "what am I about to
      # spend" line on the run button. Approximate by nature — the stored
      # `Report#cost` is what was actually charged.
      def estimated_cost = 0.0

      # Reports that read the same data every time can be cached; ones that
      # track movement should be re-run. Drives the "last run" hint only.
      def cadence = "weekly"

      # How precisely this endpoint understands "where".
      #
      #   :city     SERP, Business Data — a map-pack position is a city
      #             question, and a country would answer the wrong one
      #   :country  DataForSEO Labs, LLM Mentions, AI Keyword Data — their
      #             indexes contain no cities and reject one with a 40501
      #   :none     On-Page — no location at all
      #
      # Declared rather than inferred so a new report has to decide, instead
      # of inheriting whichever default happened to suit the last one.
      def location_granularity = :city

      # Which supported-locations list a :country report resolves against.
      # Each API publishes its own and they differ — 90, 92 and 94 entries.
      def locations_api = nil

      # The handful of numbers worth plotting across snapshots.
      #
      # A stored report is a full answer; a trend needs only its headline
      # figures, taken from every snapshot in a date range. This pulls them
      # out of `Report#data` so the controller can build a series without
      # sending twenty full payloads to the browser. Keys are the metric
      # names the UI plots; values are numbers or nil.
      def trend_point(_data) = {}

      # Props a report's page needs beyond the snapshot — state that changes
      # without a paid run (a person's checklist, say). Merged into the show
      # page's props by the controller. Most reports have none.
      def page_props = {}

      # The metrics `trend_point` returns, with labels and whether up is
      # good — so the UI can colour a delta and label an axis without
      # guessing from the key name.
      def trend_metrics = []
    end

    attr_reader :profile, :client

    def initialize(profile:, client:)
      @profile = profile
      @client = client
      @cost = 0.0
    end

    # => Hash. Raise DataForSeo::Error (or anything) to fail the report;
    # Report::Runnable records the message.
    def call
      raise NotImplementedError, "#{self.class} must implement #call"
    end

    # Accumulated across however many calls the report made. Read by the job
    # after `call` returns.
    attr_reader :cost

    # Anything a report wants the reader to know that isn't a number — a
    # field the API refused, a secondary call that didn't come back. The
    # job stores these on the snapshot; the page shows them.
    def warnings = @warnings ||= []

    private

    # Fields the drop-and-retry below will never remove: without them the
    # request means nothing, and the API's complaint is about something else.
    REQUIRED_FIELDS = %i[keyword keywords target url user_prompt model_name location_code language_code location_coordinate].freeze
    MAX_DROPS = 3

    # Every DataForSEO call a report makes should go through this, so cost is
    # totalled without each subclass remembering to.
    #
    # It also absorbs one whole class of failure. Six times now an endpoint
    # has rejected an OPTIONAL field its own documentation lists, with
    # `40501 Invalid Field: '<name>'`. The message names the field, so rather
    # than fail a report over a refinement it can live without, this drops
    # that one field and tries again — at most a few times, never a required
    # field — and records what it dropped so the page can say so.
    def fetch(path, task)
      dropped = []
      loop do
        begin
          response = client.post(path, task)
          @cost += response.cost
          warn_dropped(path, dropped) if dropped.any?
          return response
        rescue DataForSeo::Error => e
          field = droppable_field(e, task)
          raise if field.nil? || dropped.length >= MAX_DROPS

          dropped << field
          task = task.except(field)
        end
      end
    end

    def droppable_field(error, task)
      return nil unless error.status_code == 40_501

      name = error.message[/Invalid Field: '([a-z_]+)'/i, 1]&.to_sym
      return nil if name.nil? || REQUIRED_FIELDS.include?(name) || !task.key?(name)

      name
    end

    def warn_dropped(path, dropped)
      warnings << "#{path.split("/").first(2).join("/")} refused #{dropped.map { |f| "'#{f}'" }.to_sentence}; sent without."
    end

    def fetch_many(path, tasks)
      responses = client.post_many(path, tasks)
      @cost += responses.compact.sum(&:cost)
      responses
    end

    # Post a task and wait for it. Blocks the job thread — that is the point
    # of running reports in a job — polling with a slow backoff up to
    # `timeout`. The post is where DataForSEO bills, so a timeout is money
    # spent for nothing, which is why the ceiling is generous and the report
    # says so when it hits it.
    def await_task(path, task, timeout: 240, interval: 5)
      posted = client.post_task(path, task)
      @cost += posted[:cost]

      deadline = Time.current + timeout
      wait = interval
      loop do
        sleep(wait)
        response = client.task_get(path, posted[:id])
        if response
          @cost += response.cost
          return response
        end
        raise DataForSeo::Error, "DataForSEO didn't finish task #{posted[:id]} within #{timeout}s. It was charged for; try again later." if Time.current > deadline

        wait = [wait * 1.5, 30].min
      end
    end

    # The location and language params, at whatever granularity this report's
    # endpoint actually understands — always as a CODE. Three endpoints in a
    # row rejected a name; see DataForSeo::Locations. Subclasses call this
    # and don't think about it; `location_granularity` is where the thinking
    # lives.
    def locale_params
      return {} if self.class.location_granularity == :none

      {location_code: locale.location_code, language_code: locale.language_code}
    end

    # The resolved location — a country for a :country report, a city for a
    # :city one. Memoized: several reports make more than one call, and the
    # list lookup is cached but not free.
    #
    # Exposed so `call` can record what was actually asked: a report that
    # ran against somewhere other than what was configured has to be able to
    # say so, and to say WHY, because the causes have different fixes.
    def locale
      @locale ||= self.class.location_granularity == :city ? city_locale : country_locale
    end

    private

    def country_locale
      DataForSeo::Locations
        .new(client, api: self.class.locations_api)
        .resolve(country_name: profile.country_name,
                 location_code: profile.configured_location_code,
                 language_code: profile.language_code)
    end

    # A city report at the wrong location is not "indicative", it is wrong —
    # a national SERP has no map pack for a business in Cardiff — so unlike
    # the country case this does not fall back. It fails, with the fix.
    def city_locale
      iso = DataForSeo::Locations.new(client, api: "dataforseo_labs")
                                 .country_iso(country_name: profile.country_name,
                                              location_code: profile.configured_location_code)

      resolved = DataForSeo::Locations
                 .new(client, api: self.class.locations_api)
                 .resolve_city(location_name: profile.location_name,
                               location_code: profile.configured_location_code,
                               iso: iso,
                               language_code: profile.language_code)
      return resolved if resolved.exact?

      raise DataForSeo::Error, city_failure_message(resolved)
    end

    def city_failure_message(resolved)
      case resolved.reason
      when :no_country
        "No location is set for this business. Add one under Settings → Reporting as " \
        "City,Region,Country — for example Cardiff,Wales,United Kingdom."
      when :lookup_failed
        "Couldn't read DataForSEO's location list to check #{profile.location_name.inspect}. " \
        "This is usually temporary — run the report again."
      else
        "Couldn't match #{profile.location_name.inspect} to a DataForSEO location in " \
        "#{profile.country_name.presence || "that country"}. Check the spelling under Settings → Reporting, " \
        "or set the location code directly."
      end
    end

    public

    # The three fields every :country report puts in its data, so the UI can
    # render one component for all of them.
    def locale_data
      {
        location: locale.location_name,
        location_is_fallback: locale.fallback?,
        location_reason: locale.reason.to_s,
        location_requested: locale.requested.to_s,
        language: locale.language_code
      }
    end

    # Rounds a float for display without pretending to precision the source
    # doesn't have.
    def round(value, places = 2)
      return nil if value.nil?

      value.to_f.round(places)
    end
  end
end
