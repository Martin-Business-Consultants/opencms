# frozen_string_literal: true

require "rails_helper"

RSpec.describe TranslationGroup do
  def make_page(attrs = {})
    Page.create!({
      slug:        "p-#{SecureRandom.hex(3)}",
      title:       "T",
      status:      "published",
      locale:      "en",
      blocks:      [],
      schema:      {"fields" => []},
      frontmatter: {},
      seo:         {}
    }.merge(attrs))
  end

  it "groups page translations" do
    group = described_class.create!(kind: "page")
    en = make_page(locale: "en", translation_group: group)
    es = make_page(locale: "es", slug: "p-es", translation_group: group)

    expect(group.member_locales).to contain_exactly("en", "es")
    expect(group.members.pluck(:id)).to contain_exactly(en.id, es.id)
  end

  describe "Sitemap alternates" do
    it "exposes sibling translations as hreflang alternates" do
      group = described_class.create!(kind: "page")
      make_page(locale: "en", slug: "p-en", translation_group: group)
      make_page(locale: "es", slug: "p-es", translation_group: group)

      sitemap = Sitemap.new
      en_entry = sitemap.entries.find { |e| e.locale == "en" }
      expect(en_entry.alternates.map { |a| a[:locale] }).to include("es")
      expect(en_entry.alternates.find { |a| a[:locale] == "es" }[:loc]).to eq("/p-es")
    end
  end
end
