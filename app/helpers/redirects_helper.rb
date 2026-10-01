# frozen_string_literal: true

module RedirectsHelper
  # [["301 — Moved permanently", 301], …] for the status select.
  def redirect_status_options
    Redirect::STATUS_CODES.map { |code| ["#{code} — #{Redirect::STATUS_LABELS[code]}", code] }
  end
end
