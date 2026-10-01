# frozen_string_literal: true

module Reports
  # Settings › Reporting › Test: a real round trip to DataForSEO with the
  # saved credential, said in a sentence.
  #
  # It reports the balance as well as success, because "the credential works"
  # and "there is money behind it" are different questions and only one of
  # them stops a report running. It also resolves the locations, because the
  # other way a report silently goes wrong is the location: several run
  # against country-scoped endpoints, and finding out which country they
  # resolved to should not cost a paid report.
  class ConnectionTest
    Outcome = Struct.new(:ok, :message, keyword_init: true) do
      def ok? = ok
    end

    def initialize(client: nil, profile: nil)
      @client = client
      @profile = profile
    end

    def run
      @client ||= DataForSeo::Client.from_settings
      info = @client.ping
      balance = info[:balance]

      if balance.to_f <= 0
        return Outcome.new(ok: false,
          message: "Connected as #{info[:login]}, but the balance is #{money(balance)}. Reports will fail until it's topped up.")
      end

      Outcome.new(ok: true, message: "Connected as #{info[:login]}. Balance #{money(balance)}. #{locations}".strip)
    rescue DataForSeo::Error => e
      Outcome.new(ok: false, message: e.message)
    rescue StandardError => e
      Outcome.new(ok: false, message: "Connection test failed: #{e.message}")
    end

    private

    def money(value) = "$#{format("%.2f", value.to_f)}"

    # Which locations the reports will actually use, said plainly while it is
    # still free to find out. Country for Ranked keywords and the AI reports;
    # the city for Local rankings and Business profile — and the city is the
    # one that fails a run outright when it can't be matched, so it is the one
    # most worth checking here.
    def locations
      @profile ||= Profile.load
      if @profile.country_name.blank? && @profile.configured_location_code.nil?
        return "No location set yet — add one before running a report."
      end

      labs = DataForSeo::Locations.new(@client, api: "dataforseo_labs")
      country = labs.resolve(country_name: @profile.country_name, location_code: @profile.configured_location_code)
      parts = []
      parts << if country.exact?
        "Country reports will use #{country.location_name}."
      else
        "Couldn't match #{@profile.country_name.inspect} to a supported country — country reports will use the United States."
      end

      if @profile.location_name.present? || @profile.configured_location_code
        city = DataForSeo::Locations.new(@client, api: "serp_google")
          .resolve_city(location_name: @profile.location_name,
            location_code: @profile.configured_location_code,
            iso: labs.country_iso(country_name: @profile.country_name, location_code: @profile.configured_location_code))
        parts << if city.exact?
          "Local reports will use #{city.location_name} (#{city.location_code})."
        else
          "Couldn't match #{@profile.location_name.inspect} to a DataForSEO location — local reports will fail until it is fixed."
        end
      end

      parts.join(" ")
    rescue StandardError
      # The credential test succeeded; a failed lookup must not report it as
      # a failure.
      ""
    end
  end
end
