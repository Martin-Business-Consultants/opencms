# frozen_string_literal: true

# Marking a finding done: someone has since handled it.
class Recommendations::CompletionsController < ApplicationController
  include RecommendationResolution

  def create
    resolve(:mark_actioned!, :actioned, "Marked as done")
  end
end
