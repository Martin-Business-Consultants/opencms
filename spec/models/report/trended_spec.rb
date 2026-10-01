# frozen_string_literal: true

require "rails_helper"

RSpec.describe Report::Trended do
  it "gives each headline figure now and at the run compared with" do
    before = Report.new(kind: "ranked_keywords", status: "complete", data: {"top_3" => 4, "total_count" => 90})
    now = Report.new(kind: "ranked_keywords", status: "complete", data: {"top_3" => 7, "total_count" => 100})

    metrics = now.metrics(against: before)

    expect(metrics.first.keys).to eq(%i[key label good now previous])
    top_3 = metrics.find { it[:key] == now.definition.trend_metrics.first[:key] }
    expect(top_3[:now]).not_to be_nil
    expect(now.metrics(against: nil).map { it[:previous] }.uniq).to eq([nil])
  end
end
