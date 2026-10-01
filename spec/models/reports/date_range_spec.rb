# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::DateRange do
  def parse(params) = described_class.parse(ActionController::Parameters.new(params))

  it "defaults to the last 90 days" do
    range = parse({})
    expect(range.preset).to eq("90d")
    expect(range.starts_at).to be_within(1.minute).of(90.days.ago.beginning_of_day)
    expect(range.ends_at).to be_nil
  end

  it "accepts a known preset and ignores an unknown one" do
    expect(parse(range: "7d").preset).to eq("7d")
    expect(parse(range: "6h").preset).to eq("90d")
  end

  it "is unbounded for 'all'" do
    range = parse(range: "all")
    expect(range.starts_at).to be_nil
    expect(range.ends_at).to be_nil
  end

  it "takes a custom from/to pair over a preset" do
    range = parse(range: "7d", from: "2026-08-01", to: "2026-08-31")
    expect(range).to be_custom
    expect(range.starts_at).to eq(Date.new(2026, 8, 1).beginning_of_day)
    # Through the end of the day named, so today's snapshots count.
    expect(range.ends_at).to eq(Date.new(2026, 8, 31).end_of_day)
  end

  it "tolerates a half-open custom range and a garbage date" do
    expect(parse(from: "2026-08-01").ends_at).to be_nil
    expect(parse(to: "2026-08-31").starts_at).to be_nil
    expect(parse(from: "not-a-date").preset).to eq("90d")
  end

  it "round-trips through URL params" do
    expect(parse(range: "30d").to_params).to eq({range: "30d"})
    expect(parse(from: "2026-08-01", to: "2026-08-31").to_params)
      .to eq({from: "2026-08-01", to: "2026-08-31"})
  end

  it "scopes a relation by created_at" do
    relation = Report.all
    scoped = parse(range: "7d").scope(relation)
    expect(scoped.to_sql).to include("created_at")
    expect(parse(range: "all").scope(relation).to_sql).not_to include("created_at\" >=")
  end
end
