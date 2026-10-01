# frozen_string_literal: true

# What reporting has cost. A per-call price on a button is abstract and a
# running total is not.
module Report::Priced
  extend ActiveSupport::Concern

  class_methods do
    def spent_this_month = complete.where(created_at: Time.current.beginning_of_month..).sum(:cost).to_f

    # Totals, plus what fell inside a date range's scope (Reports::DateRange).
    def spend(range)
      in_range = range.scope(complete)
      {
        total: complete.sum(:cost).to_f,
        this_month: spent_this_month,
        runs: complete.count,
        in_range: in_range.sum(:cost).to_f,
        runs_in_range: in_range.count
      }
    end
  end
end
