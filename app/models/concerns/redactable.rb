# frozen_string_literal: true

# Globals and settings are free-form, and some hold secrets (an API key, a
# webhook signing secret). What the API reads back has anything whose key
# name suggests a secret masked to its last four characters; writes still set
# the real value.
module Redactable
  extend ActiveSupport::Concern

  SECRET_KEY = /\b(api[_-]?key|secret|token|password|client[_-]?secret)\b/i

  def redacted_data = redact(data)

  private

  def redact(value)
    case value
    when Hash
      value.each_with_object({}) do |(k, v), out|
        out[k] = if SECRET_KEY.match?(k.to_s) && v.is_a?(String) && !v.empty?
          mask(v)
        else
          redact(v)
        end
      end
    when Array
      value.map { |v| redact(v) }
    else
      value
    end
  end

  def mask(str)
    return "" if str.empty?

    "***#{str[-4..]}"
  end
end
