# frozen_string_literal: true

module Reports
  # The management half of citations: what a person has done about each
  # directory, kept apart from what the audit found.
  #
  # The audit says "missing" or "NAP differs"; the person says "submitted on
  # the 3rd" or "ignore — they want money". Both are true at once, and only
  # the person's half changes without a paid run, so it lives in the site's
  # settings rather than on a snapshot. One row per directory, last write wins.
  module CitationStatuses
    SETTING_KEY = "citations"
    STATUSES = %w[todo submitted live needs_fix ignored].freeze
    NOTE_LIMIT = 500

    module_function

    def all = Setting.get(SETTING_KEY)

    def known_status?(status) = STATUSES.include?(status.to_s)

    def update(directory, status:, note: nil, by: nil)
      entry = {
        "status" => status.to_s,
        "note" => note.to_s.strip.truncate(NOTE_LIMIT),
        "updated_at" => Time.current.iso8601,
        "updated_by" => by&.email
      }
      Setting.set(SETTING_KEY, directory => entry)
      Event.record("citation.status_updated", directory: directory, status: status.to_s)
    end
  end
end
