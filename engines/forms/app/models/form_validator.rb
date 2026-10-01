# frozen_string_literal: true

# FormValidator extracts field-shape validation and submission validation logic
# from Form. It is pure (no AR) and can be reused by form preview or API layers.
class FormValidator
  FIELD_TYPES = %w[text email tel url textarea select radio checkbox file].freeze
  OPTIONED_TYPES = %w[select radio].freeze
  DEFAULT_MAX_FILE_BYTES = 10 * 1024 * 1024
  HONEYPOT_FIELD = "_hp"

  class << self
    def validate_fields_shape(fields)
      errors = []
      return ["must be an array"] unless fields.is_a?(Array)

      seen = {}
      fields.each_with_index do |fd, i|
        prefix = "fields[#{i}]"

        unless fd.is_a?(Hash)
          errors << "#{prefix} must be an object"
          next
        end

        name = fd["name"]
        type = fd["type"]
        label = fd["label"]

        if !name.is_a?(String) || name.strip.empty?
          errors << "#{prefix}.name is required"
        elsif seen[name]
          errors << "#{prefix}.name '#{name}' is duplicated"
        else
          seen[name] = true
        end

        if !label.is_a?(String) || label.strip.empty?
          errors << "#{prefix}.label is required"
        end

        unless FIELD_TYPES.include?(type)
          errors << "#{prefix}.type must be one of #{FIELD_TYPES.join(", ")}"
          next
        end

        if OPTIONED_TYPES.include?(type)
          opts = fd["options"]
          unless opts.is_a?(Array) && opts.any? && opts.all? { |o| o.is_a?(Hash) && o["value"].is_a?(String) && o["label"].is_a?(String) }
            errors << "#{prefix}.options must be an array of {value, label} objects"
          end
        end
      end
      errors
    end

    # Validate an inbound submission's `data` hash and `files` map.
    # Returns { "field_name" => [msg, ...] } — empty when valid.
    def validate_submission(fields, data, files = {})
      out = {}
      data = {} unless data.is_a?(Hash)

      Array(fields).each do |fd|
        next unless fd.is_a?(Hash)

        name     = fd["name"]
        type     = fd["type"]
        required = fd["required"] == true

        if type == "file"
          uploaded = Array(files[name]).reject(&:blank?)
          if required && uploaded.empty?
            (out[name] ||= []) << "is required"
            next
          end
          next if uploaded.empty?

          max_bytes = fd["max_size"].is_a?(Integer) ? fd["max_size"] : DEFAULT_MAX_FILE_BYTES
          accept    = fd["accept"].is_a?(String) ? fd["accept"] : nil

          uploaded.each do |upload|
            if upload.size > max_bytes
              (out[name] ||= []) << "must be smaller than #{max_bytes} bytes"
            end
            if accept && !accepts?(accept, upload)
              (out[name] ||= []) << "type not allowed"
            end
          end
          next
        end

        val = data[name]
        if blank_value?(val)
          (out[name] ||= []) << "is required" if required
          next
        end

        case type
        when "email"
          (out[name] ||= []) << "is not a valid email" unless val.to_s.match?(URI::MailTo::EMAIL_REGEXP)
        when "url"
          (out[name] ||= []) << "is not a valid URL" unless val.to_s.match?(%r{\Ahttps?://[^\s]+\z})
        when "select", "radio"
          allowed = Array(fd["options"]).filter_map { |o| o["value"] if o.is_a?(Hash) }
          (out[name] ||= []) << "must be one of #{allowed.join(", ")}" unless allowed.include?(val.to_s)
        when "checkbox"
          # Accept any present value; no further validation.
        end
      end

      out
    end

    private

    def blank_value?(val)
      val.nil? || val == "" || (val.is_a?(Array) && val.empty?)
    end

    def accepts?(accept_str, upload)
      accept_str.split(",").map(&:strip).reject(&:empty?).any? do |token|
        if token.start_with?(".")
          upload.original_filename.to_s.downcase.end_with?(token.downcase)
        elsif token.end_with?("/*")
          upload.content_type.to_s.start_with?(token[0..-2])
        else
          upload.content_type.to_s == token
        end
      end
    end
  end
end
