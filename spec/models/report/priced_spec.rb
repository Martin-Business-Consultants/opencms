# frozen_string_literal: true

require "rails_helper"

RSpec.describe Report::Priced do
  before { Report.delete_all }

  it "totals what finished runs cost, this month and in a range" do
    travel_to Time.utc(2026, 9, 15, 12) do
      Report.create!(kind: "backlinks", status: "complete", cost: 0.25, created_at: Time.utc(2026, 8, 20))
      Report.create!(kind: "backlinks", status: "complete", cost: 0.5, created_at: Time.utc(2026, 9, 10))
      Report.create!(kind: "backlinks", status: "failed", cost: 9, created_at: Time.utc(2026, 9, 11))

      spend = Report.spend(Reports::DateRange.parse({}))

      expect(spend).to include(total: 0.75, this_month: 0.5, runs: 2)
      expect(Report.spent_this_month).to eq(0.5)
    end
  end
end
