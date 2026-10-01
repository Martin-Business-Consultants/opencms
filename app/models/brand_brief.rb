# frozen_string_literal: true

# Settings › Brand context: the brief an agent writes to (voice, audience,
# facts to keep straight, house style), delivered with the manifest.
module BrandBrief
  SETTING_KEY = "brand"
  FIELDS = %w[brand_voice audience key_facts style_notes].freeze

  module_function

  # Blank fields are dropped rather than sent as empty strings, so a consumer
  # can treat "absent" as "not specified". {} when nothing is filled in.
  def to_h
    data = Setting.get(SETTING_KEY)
    FIELDS.each_with_object({}) do |field, out|
      value = data[field].to_s.strip
      out[field] = value unless value.empty?
    end
  end
end
