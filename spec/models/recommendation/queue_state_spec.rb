# frozen_string_literal: true

require "rails_helper"

# The size of a queue says almost nothing. Forty findings that turned over
# last week is a working queue; four that have sat for a month is a broken
# one. So what this pins is the ordering of facts, not the arithmetic.
RSpec.describe Recommendation::QueueState do
  def finding(created_at: Time.current, impact: 0, title: "Title is too long")
    Recommendation.create!(kind: "metadata", title: title, impact: impact, created_at: created_at)
  end

  def state(open) = described_class.new(open: open)

  it "says nothing is waiting rather than reporting a zero" do
    result = state([]).to_h

    expect(result[:severity]).to eq("success")
    expect(result[:headline]).to eq("Nothing is waiting on you")
  end

  # Age beats volume. A queue of four that nobody has touched in a month is
  # the thing to say out loud, not "4 findings waiting".
  it "leads with age over count" do
    old = Array.new(4) { finding(created_at: 40.days.ago) }

    result = state(old).to_h

    expect(result[:severity]).to eq("danger")
    expect(result[:headline]).to eq("4 findings have been open over a month")
    expect(result[:detail]).to include("the agent will keep finding it")
  end

  it "counts a large fresh queue as a queue that stopped turning over" do
    result = state(Array.new(100) { finding }).to_h

    expect(result[:severity]).to eq("danger")
    expect(result[:headline]).to include("stopped turning over")
  end

  it "names high impact when nothing is old" do
    result = state([finding(impact: 5), finding(impact: 1)]).to_h

    expect(result[:severity]).to eq("warning")
    expect(result[:headline]).to eq("1 finding rated high impact")
  end

  it "falls back to the plain count when nothing stands out" do
    result = state([finding, finding]).to_h

    expect(result[:severity]).to eq("info")
    expect(result[:headline]).to eq("2 findings waiting on you")
    expect(result[:attention_count]).to eq(0)
  end

  # One finding that is both old and high impact is one item, not two.
  it "does not list the same finding twice" do
    result = state([finding(created_at: 40.days.ago, impact: 5)]).to_h

    expect(result[:items].size).to eq(1)
    expect(result[:items].first[:severity]).to eq("danger")
  end
end
