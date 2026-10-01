# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sitemapped do
  def make_page(seo = {})
    Page.create!(slug: "p-#{SecureRandom.hex(3)}", title: "A page", status: "published", locale: "en", seo: seo)
  end

  it "sets only the settings it's given, normalised" do
    page = make_page("title" => "Kept")
    page.change_sitemap_settings("sitemap_priority" => "1.7", "sitemap_changefreq" => "hourly", "noindex" => "0")

    expect(page.seo).to eq("title" => "Kept", "sitemap_priority" => 1.0, "sitemap_changefreq" => "hourly", "noindex" => false)
  end

  it "clears a setting sent blank or unparseable, so the default applies" do
    page = make_page("sitemap_priority" => 0.4, "sitemap_changefreq" => "daily", "nofollow" => true)
    page.change_sitemap_settings(sitemap_priority: "", sitemap_changefreq: "bogus", nofollow: "")

    expect(page.seo).to eq({})
  end

  it "leaves settings it isn't given alone" do
    page = make_page("noindex" => true)
    page.change_sitemap_settings("sitemap_priority" => "0.25")

    expect(page.seo).to eq("noindex" => true, "sitemap_priority" => 0.25)
  end

  it "records a sitemap row's update under one action for pages and entries" do
    page = make_page

    expect { page.track_sitemap_update(source: "page") }.to change(AuditLog, :count).by(1)
    expect(AuditLog.last).to have_attributes(action: "sitemap.entry_updated", metadata: {"source" => "page"})
  end

  it "finds the record a sitemap row stands for" do
    page = make_page

    expect(Sitemap.record_for("page", page.id)).to eq(page)
    expect(Sitemap.record_for("collection_entry", page.id)).to be_nil
    expect(Sitemap.record_for("user", 1)).to be_nil
  end
end
