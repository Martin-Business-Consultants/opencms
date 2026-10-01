# frozen_string_literal: true

require "rails_helper"

RSpec.describe Recommendation::Listing do
  def file(title, **attrs)
    Recommendation.create!({kind: "content_gap", title: title}.merge(attrs))
  end

  it "lists the open queue by impact when no status is asked for" do
    low = file("Low", impact: 1)
    high = file("High", impact: 5)
    file("Done", status: "dismissed")

    expect(Recommendation.listed.to_a).to eq([high, low])
  end

  it "lists one status, newest first" do
    old = file("Old", status: "dismissed", created_at: 2.days.ago)
    new = file("New", status: "dismissed")

    expect(Recommendation.listed(status: "dismissed").to_a).to eq([new, old])
  end

  it "filters by kind and ignores unknown statuses and kinds" do
    gap = file("Gap")
    meta = file("Meta", kind: "metadata")

    expect(Recommendation.listed(kind: "metadata").to_a).to eq([meta])
    expect(Recommendation.listed(kind: "nope").to_a).to contain_exactly(gap, meta)
  end

  it "caps the page size" do
    3.times { file("F#{it}") }

    expect(Recommendation.listed(limit: "2").size).to eq(2)
    expect(Recommendation.listed(limit: "999").limit_value).to eq(200)
    expect(Recommendation.listed.limit_value).to eq(100)
  end
end
