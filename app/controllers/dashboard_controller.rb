# frozen_string_literal: true

# The getting-started checklist, and whatever plugins put on the dashboard
# (the :dashboard slot). Dismissing the checklist and ticking off a step are
# Dashboard::ChecklistDismissals and Dashboard::ChecklistAcknowledgements.
class DashboardController < ApplicationController
  skip_authorization

  def index
    @checklist = OnboardingChecklist.payload
  end
end
