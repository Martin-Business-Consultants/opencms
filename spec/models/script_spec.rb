# frozen_string_literal: true

require "rails_helper"

RSpec.describe Script do
  before { Script.delete_all }

  it "needs a URL or code, and a real category" do
    s = Script.new(name: "Empty", category: "analytics")
    expect(s).not_to be_valid
    expect(s.errors[:base].join).to match(/URL, inline code/)

    s.code = "console.log(1)"
    expect(s).to be_valid

    s.category = "tracking"
    expect(s).not_to be_valid

    s.category = "marketing"
    s.src = "javascript:alert(1)"
    expect(s).not_to be_valid
    expect(s.errors[:src].join).to match(/http/)
  end

  it "orders necessary first and marketing last" do
    Script.create!(name: "Pixel", category: "marketing", code: "1")
    Script.create!(name: "Fonts", category: "necessary", code: "1")
    Script.create!(name: "GA", category: "analytics", code: "1")
    expect(Script.ordered.pluck(:category)).to eq(%w[necessary analytics marketing])
  end

  describe Scripts::Presets do
    it "fills the vendor snippet with the ID and nothing else" do
      attrs = Scripts::Presets.build("ga4", id: " G-ABC123 ")
      expect(attrs[:src]).to eq("https://www.googletagmanager.com/gtag/js?id=G-ABC123")
      expect(attrs[:code]).to include("gtag('config', 'G-ABC123')")
      expect(attrs[:category]).to eq("analytics")
      expect(Script.new(attrs)).to be_valid
    end

    it "refuses an ID that could break out of the snippet" do
      expect { Scripts::Presets.build("meta_pixel", id: "123'); alert(1); ('") }
        .to raise_error(Scripts::Presets::InvalidId)
      expect { Scripts::Presets.build("nope", id: "1") }.to raise_error(Scripts::Presets::UnknownPreset)
    end

    it "every preset builds a valid script" do
      Scripts::Presets::ALL.each do |p|
        expect(Script.new(Scripts::Presets.build(p[:key], id: "test-id"))).to be_valid, p[:key]
        expect(p[:category]).to be_in(Script::CATEGORIES)
      end
    end
  end
end
