# frozen_string_literal: true

module DataForSeo
  # Anything DataForSEO refused to answer properly.
  #
  # Carries the API's own `status_code` where there was one, because those
  # codes are the difference between "your filter is malformed" and "your
  # balance is empty" — and only one of those is worth retrying.
  class Error < StandardError
    attr_reader :status_code, :status_message

    def initialize(message, status_code: nil, status_message: nil)
      @status_code = status_code
      @status_message = status_message
      super(message)
    end
  end
end
