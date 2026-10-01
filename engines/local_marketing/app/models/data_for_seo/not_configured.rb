# frozen_string_literal: true

module DataForSeo
  # No usable credential — none saved, or the one saved was rejected.
  #
  # Its own class rather than a nil return so a caller can't mistake "no key"
  # for "no data". They look identical in a report and the fixes are nothing
  # alike: one is a settings page, the other is a business problem.
  class NotConfigured < Error; end
end
