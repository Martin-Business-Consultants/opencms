# frozen_string_literal: true

require "rails_helper"

# The regression this exists for: the AI Optimization endpoints index by
# country, so the city-level location that makes Local rankings correct comes
# back from them as `40501 Invalid Field: 'location_name'`.
RSpec.describe DataForSeo::Locations do
  before { Rails.cache.clear }

  let(:list) do
    [
      {"location_code" => 2840, "location_name" => "United States",
       "available_languages" => [{"language_code" => "en", "language_name" => "English"}]},
      {"location_code" => 2826, "location_name" => "United Kingdom",
       "available_languages" => [{"language_code" => "en", "language_name" => "English"}]},
      {"location_code" => 2276, "location_name" => "Germany",
       "available_languages" => [{"language_code" => "de", "language_name" => "German"}]}
    ]
  end

  let(:client) { instance_double(DataForSeo::Client, get: list) }

  subject(:locations) { described_class.new(client, api: "llm_mentions") }

  it "resolves a country name to the code the endpoint accepts" do
    resolved = locations.resolve(country_name: "United Kingdom", language_code: "en")

    expect(resolved.location_code).to eq(2826)
    expect(resolved.language_code).to eq("en")
    expect(resolved).to be_exact
  end

  it "resolves by location_code when only that is configured" do
    # The case that reported the United States when the site had told us
    # the country perfectly well: a code set, the name left blank.
    resolved = locations.resolve(location_code: 2826)

    expect(resolved.location_code).to eq(2826)
    expect(resolved.location_name).to eq("United Kingdom")
    expect(resolved).to be_exact
  end

  it "ignores a city-level code, which is not in a country list" do
    resolved = locations.resolve(country_name: "United Kingdom", location_code: 1_006_886)

    expect(resolved.location_code).to eq(2826)
    expect(resolved).to be_exact
  end

  it "is case-insensitive and understands the obvious aliases" do
    expect(locations.resolve(country_name: "uk").location_code).to eq(2826)
    expect(locations.resolve(country_name: "Wales").location_code).to eq(2826)
    expect(locations.resolve(country_name: "USA").location_code).to eq(2840)
  end

  describe "why it fell back" do
    it "says unsupported when the country is genuinely not covered" do
      resolved = locations.resolve(country_name: "Atlantis")

      expect(resolved.location_code).to eq(2840)
      expect(resolved.reason).to eq(:unsupported)
      expect(resolved.requested).to eq("Atlantis")
    end

    it "says no_country when nothing was configured to resolve" do
      expect(locations.resolve(country_name: "").reason).to eq(:no_country)
    end

    # The distinction that matters: claiming DataForSEO has no data for a
    # country, when in fact the list could not be read, sends someone to fix
    # something that is not broken.
    it "says lookup_failed when the list could not be read" do
      failing = instance_double(DataForSeo::Client)
      allow(failing).to receive(:get).and_raise(DataForSeo::Error.new("boom"))

      resolved = described_class.new(failing, api: "llm_mentions")
                               .resolve(country_name: "United Kingdom")

      expect(resolved.location_code).to eq(2840)
      expect(resolved.reason).to eq(:lookup_failed)
    end

    it "distinguishes 'could not read the list' from 'the list is empty'" do
      failing = instance_double(DataForSeo::Client)
      allow(failing).to receive(:get).and_raise(DataForSeo::Error.new("boom"))

      expect(described_class.new(failing, api: "llm_mentions").all).to be_nil
      expect(described_class.new(instance_double(DataForSeo::Client, get: []), api: "llm_mentions").all).to eq([])
    end
  end

  it "swaps a language the location has no data in" do
    # Germany is de-only in this list; asking for English would 40501 the
    # same way a bad location does.
    expect(locations.resolve(country_name: "Germany", language_code: "en").language_code).to eq("de")
  end

  it "keeps the requested language when the location supports it" do
    expect(locations.resolve(country_name: "United Kingdom", language_code: "en").language_code).to eq("en")
  end

  it "caches the list so a scheduled run doesn't refetch it every time" do
    expect(client).to receive(:get).once.and_return(list)

    3.times { locations.resolve(country_name: "United Kingdom") }
  end

  it "uses each API's own list — they are not the same" do
    expect(client).to receive(:get).with("ai_optimization/ai_keyword_data/locations_and_languages")
    described_class.new(client, api: "ai_keyword_data").all
  end

  it "knows DataForSEO Labs is country-scoped too" do
    expect(client).to receive(:get).with("dataforseo_labs/locations_and_languages")
    described_class.new(client, api: "dataforseo_labs").all
  end

  describe "cities" do
    let(:uk_cities) do
      [
        {"location_code" => 2826, "location_name" => "United Kingdom", "location_type" => "Country", "country_iso_code" => "GB"},
        {"location_code" => 20_339, "location_name" => "Wales,United Kingdom", "location_type" => "Region", "country_iso_code" => "GB"},
        {"location_code" => 1_006_886, "location_name" => "Cardiff,Wales,United Kingdom", "location_type" => "City", "country_iso_code" => "GB"},
        {"location_code" => 1_006_900, "location_name" => "Cardiff Bay,Wales,United Kingdom", "location_type" => "City", "country_iso_code" => "GB"},
        {"location_code" => 1_006_950, "location_name" => "Newport,Wales,United Kingdom", "location_type" => "City", "country_iso_code" => "GB"}
      ]
    end
    let(:city_client) { instance_double(DataForSeo::Client, get: uk_cities) }
    subject(:cities) { described_class.new(city_client, api: "serp_google") }

    it "fetches the per-country list, so it never has to hold 100k rows" do
      expect(city_client).to receive(:get).with("serp/google/locations/gb").and_return(uk_cities)
      cities.resolve_city(location_name: "Cardiff,Wales,United Kingdom", iso: "GB")
    end

    it "matches the full name to the character, after fixing the spaces people type" do
      # The value that produced 40501 — and the reason the code, not the
      # name, is what gets sent.
      resolved = cities.resolve_city(location_name: "Cardiff, Wales, United Kingdom", iso: "GB")
      expect(resolved.location_code).to eq(1_006_886)
      expect(resolved.location_name).to eq("Cardiff,Wales,United Kingdom")
      expect(resolved).to be_exact
    end

    it "matches on the city alone when that is all that was typed" do
      expect(cities.resolve_city(location_name: "Cardiff", iso: "GB").location_code).to eq(1_006_886)
      # A partial hierarchy narrows, and never picks the Region row.
      expect(cities.resolve_city(location_name: "Newport, Wales", iso: "GB").location_code).to eq(1_006_950)
    end

    it "trusts an explicitly-set code without a lookup" do
      expect(city_client).not_to receive(:get)
      resolved = cities.resolve_city(location_name: "", location_code: 1_006_886, iso: "GB")
      expect(resolved.location_code).to eq(1_006_886)
      expect(resolved.reason).to eq(:configured)
      expect(resolved).to be_exact
    end

    it "says why when it can't resolve" do
      expect(cities.resolve_city(location_name: "Atlantis", iso: "GB").reason).to eq(:unsupported)
      expect(cities.resolve_city(location_name: "Cardiff", iso: nil).reason).to eq(:no_country)
    end

    # Its own example: the list is cached under a key the passing lookups
    # above would have warmed, and a warm cache never asks the client.
    it "says lookup_failed when the city list can't be read" do
      failing = instance_double(DataForSeo::Client)
      allow(failing).to receive(:get).and_raise(DataForSeo::Error.new("boom"))
      resolved = described_class.new(failing, api: "serp_google").resolve_city(location_name: "Cardiff", iso: "GB")
      expect(resolved.reason).to eq(:lookup_failed)
    end

    it "uses Business Data's own list — it is not the SERP list" do
      expect(city_client).to receive(:get).with("business_data/google/locations/gb").and_return(uk_cities)
      described_class.new(city_client, api: "business_data_google").resolve_city(location_name: "Cardiff", iso: "GB")
    end
  end

  describe "#country_iso" do
    it "reads the ISO code off the country row, the key the city lists are filed under" do
      with_iso = list.map { |row| row.merge("country_iso_code" => {2840 => "US", 2826 => "GB", 2276 => "DE"}[row["location_code"]]) }
      iso_client = instance_double(DataForSeo::Client, get: with_iso)
      expect(described_class.new(iso_client, api: "dataforseo_labs").country_iso(country_name: "Wales")).to eq("GB")
      expect(described_class.new(iso_client, api: "dataforseo_labs").country_iso(country_name: "Atlantis")).to be_nil
    end
  end

  describe "#supports?" do
    it "answers before anyone spends money finding out" do
      expect(locations.supports?("United Kingdom")).to be(true)
      expect(locations.supports?("Atlantis")).to be(false)
    end

    it "is nil, not false, when it could not check" do
      failing = instance_double(DataForSeo::Client)
      allow(failing).to receive(:get).and_raise(DataForSeo::Error.new("boom"))

      expect(described_class.new(failing, api: "llm_mentions").supports?("United Kingdom")).to be_nil
    end
  end

  it "refuses an API it doesn't know" do
    expect { described_class.new(client, api: "serp") }.to raise_error(ArgumentError)
  end
end
