# frozen_string_literal: true

module DataForSeo
  # One successful task's answer.
  #
  # `cost` is what DataForSEO actually charged rather than the published list
  # price, which varies with the parameters sent — it is the number worth
  # storing on the Report.
  Response = Struct.new(:result, :cost, :task_id, :time, keyword_init: true) do
    def first = result.first

    def empty? = result.blank?
  end
end
