# frozen_string_literal: true

# A webhook's custom headers as the admin form edits them: one "Name: value"
# per line. A line that isn't a header is a validation error, not dropped.
module Webhook::EditableHeaders
  extend ActiveSupport::Concern

  included do
    validate :validate_headers_text
  end

  def headers_text
    headers.to_h.map { |name, value| "#{name}: #{value}" }.join("\n")
  end

  def headers_text=(text)
    @headers_text_error = nil
    parsed = {}

    text.to_s.each_line do |raw|
      line = raw.strip
      next if line.empty?

      name, value = line.split(":", 2)
      if value.nil?
        @headers_text_error = "has a line that isn’t “Name: value”: #{line}"
        break
      elsif name.strip.empty?
        @headers_text_error = "has a line with no header name: #{line}"
        break
      end
      parsed[name.strip] = value.strip
    end

    self.headers = parsed unless @headers_text_error
  end

  private

  def validate_headers_text
    errors.add(:headers, @headers_text_error) if @headers_text_error
  end
end
