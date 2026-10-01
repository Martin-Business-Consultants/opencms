# frozen_string_literal: true

# Dismissing a finding: not worth doing.
class Recommendations::DismissalsController < ApplicationController
  include RecommendationResolution

  def create
    resolve(:dismiss!, :dismissed, "Dismissed")
  end
end
