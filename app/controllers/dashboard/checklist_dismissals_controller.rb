# frozen_string_literal: true

# Hiding the dashboard's getting-started checklist for good.
class Dashboard::ChecklistDismissalsController < ApplicationController
  skip_authorization

  def create
    OnboardingChecklist.dismiss!
    redirect_to dashboard_path
  end
end
