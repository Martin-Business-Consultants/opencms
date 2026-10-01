# frozen_string_literal: true

# Ticking off a checklist step the CMS can't detect for itself (scaffolding
# the site happens on someone's machine), and unticking it.
class Dashboard::ChecklistAcknowledgementsController < ApplicationController
  skip_authorization

  def create
    OnboardingChecklist.acknowledge!(params[:key].to_s)
    redirect_to dashboard_path
  end

  def destroy
    OnboardingChecklist.unacknowledge!(params[:key].to_s)
    redirect_to dashboard_path
  end
end
