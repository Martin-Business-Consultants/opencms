# frozen_string_literal: true

module SubmissionsHelper
  # The first non-blank answer, which is usually the name or the message.
  def submission_preview(submission)
    submission.data.to_h.values.map(&:to_s).find { |value| !value.strip.empty? }.to_s.truncate(120)
  end

  def submission_form_options(forms)
    [["All forms", nil]] + forms.map { |form| [form.title, form.slug] }
  end
end
