# frozen_string_literal: true

module Reports
  # What a person has decided about a site-audit finding: "not a problem
  # here", with who said so and when.
  #
  # Kept in the site's settings rather than on the snapshot so it holds
  # across runs — a finding dismissed on Monday is still dismissed after the
  # weekly refresh. Keyed by the finding's key, which is stable for the same
  # problem (the same vendor, the same form), so a dismissal never hides a
  # different finding that happens to have the same words.
  module Dismissals
    SETTING_KEY = "site_audit"
    NOTE_LIMIT = 300

    module_function

    def all
      Setting.get(SETTING_KEY)["dismissed"] || {}
    end

    def dismissed?(key) = all.key?(key.to_s)

    def dismiss!(key, by: nil, note: nil)
      entry = {"at" => Time.current.iso8601, "by" => by&.email, "note" => note.to_s.strip.truncate(NOTE_LIMIT).presence}.compact
      Setting.set(SETTING_KEY, "dismissed" => all.merge(key.to_s => entry))
      Event.record("site_audit.dismissed", key: key.to_s)
    end

    def restore!(key)
      Setting.set(SETTING_KEY, "dismissed" => all.except(key.to_s))
      Event.record("site_audit.restored", key: key.to_s)
    end

    # The findings a person still has to look at — the latest audit's, minus
    # the dismissed ones.
    def open(findings)
      dismissed = all
      Array(findings).reject { |f| dismissed.key?((f[:key] || f["key"]).to_s) }
    end
  end
end
