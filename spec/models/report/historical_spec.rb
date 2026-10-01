# frozen_string_literal: true

require "rails_helper"

RSpec.describe Report::Historical do
  before { Report.delete_all }

  it "finds the run before, of the same kind and finished" do
    old = Report.create!(kind: "backlinks", status: "complete", created_at: 3.days.ago)
    Report.create!(kind: "backlinks", status: "failed", created_at: 2.days.ago)
    Report.create!(kind: "ranked_keywords", status: "complete", created_at: 2.days.ago)
    latest = Report.create!(kind: "backlinks", status: "complete", created_at: 1.day.ago)

    expect(latest.previous).to eq(old)
    expect(old.previous).to be_nil
    expect(Report.latest_by_kind.transform_values(&:id)).to include("backlinks" => latest.id)
  end

  it "is stale after its cadence's window" do
    report = Report.new(kind: "backlinks", created_at: 11.days.ago)

    expect(report.stale?("weekly")).to be(true)
    expect(report.stale?("monthly")).to be(false)
    expect(Report.stale_after(nil)).to eq(30.days)
  end
end
