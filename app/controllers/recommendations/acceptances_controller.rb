# frozen_string_literal: true

# Accepting a finding: it's worth doing. The change still goes through the ordinary edit and review path.
class Recommendations::AcceptancesController < ApplicationController
  include RecommendationResolution

  def create
    resolve(:accept!, :accepted, "Accepted")
  end
end
