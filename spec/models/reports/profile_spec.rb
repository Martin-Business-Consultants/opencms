# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::Profile do
  def profile(data = {}, general = {})
    described_class.new(data, general)
  end

  describe "#domain" do
    it "strips the scheme, www and any path — every DataForSEO target wants a bare host" do
      expect(profile("domain" => "https://www.acme.co.uk/storage").domain).to eq("acme.co.uk")
    end

    it "falls back to the published site URL rather than making the user type it twice" do
      expect(profile({}, "site_base_url" => "https://www.acme.co.uk").domain).to eq("acme.co.uk")
    end

    it "prefers an explicit domain over the site URL" do
      subject = profile({"domain" => "shop.acme.co.uk"}, "site_base_url" => "https://acme.co.uk")
      expect(subject.domain).to eq("shop.acme.co.uk")
    end

    it "is blank rather than raising on an unparseable value" do
      expect(profile("domain" => "http://[").domain).to eq("")
    end
  end

  describe "list fields" do
    it "accepts a textarea's newlines and a CSV alike, trimming and de-duping" do
      subject = profile("tracked_keywords" => "storage cardiff\n  self storage , storage cardiff\n\n")
      expect(subject.tracked_keywords).to eq(["storage cardiff", "self storage"])
    end

    it "accepts an array unchanged" do
      subject = profile("tracked_keywords" => ["a", "b"])
      expect(subject.tracked_keywords).to eq(%w[a b])
    end
  end

  describe "#brand_terms" do
    it "defaults to the business name, since that is what an AI would call it" do
      expect(profile("business_name" => "Acme Storage").brand_terms).to eq(["Acme Storage"])
    end

    it "uses the explicit list when there is one" do
      subject = profile("business_name" => "Acme Storage", "brand_terms" => "Acme\nAcme Self Storage")
      expect(subject.brand_terms).to eq(["Acme", "Acme Self Storage"])
    end
  end

  describe "#audit_urls" do
    it "defaults to the home page rather than making the report unrunnable" do
      subject = profile({}, "site_base_url" => "https://acme.co.uk/")
      expect(subject.audit_urls).to eq(["https://acme.co.uk"])
    end
  end

  describe "#location_params" do
    it "prefers the name a human typed and can check" do
      subject = profile("location_name" => "Cardiff,Wales,United Kingdom", "location_code" => 2826)
      expect(subject.location_params).to eq({location_name: "Cardiff,Wales,United Kingdom"})
    end

    it "falls back to the code, defaulting to DataForSEO's own" do
      expect(profile.location_params).to eq({location_code: 2840})
    end
  end

  describe "#missing" do
    it "names the fields a report needs and doesn't have" do
      subject = profile("business_name" => "Acme Storage")
      expect(subject.missing([:business_name, :tracked_keywords])).to eq([:tracked_keywords])
    end
  end

  describe "the rank map" do
    it "clamps the grid to an odd size and the spacing to a sane range" do
      expect(profile.map_grid_size).to eq(5)
      expect(profile("map_grid_size" => 7).map_grid_size).to eq(7)
      expect(profile("map_grid_size" => 4).map_grid_size).to eq(5)
      expect(profile("map_spacing_km" => "0.5").map_spacing_km).to eq(0.5)
      expect(profile("map_spacing_km" => "900").map_spacing_km).to eq(1.5)
    end

    it "defaults the map keywords to the first three tracked, since every cell is a paid call" do
      subject = profile("tracked_keywords" => "a\nb\nc\nd")
      expect(subject.map_keywords).to eq(%w[a b c])
      expect(profile("tracked_keywords" => "a\nb", "map_keywords" => "x").map_keywords).to eq(["x"])
    end
  end
end
