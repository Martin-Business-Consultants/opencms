# frozen_string_literal: true

# The site's visual identity (Settings › Branding), stored under
# Setting["branding"]: logo, favicon, colours, font, corners, shadow.
#
# The public site reads the raw setting. The admin reads it through here:
# `stylesheet` turns the colour and font into overrides of Fizzy's tokens,
# served as /branding.css, and only ever from values that passed the checks
# below — the setting is written by admins, but it still ends up inside CSS.
class Branding
  KEY = "branding"

  PERMITTED = %i[logo_id favicon_id primary_color secondary_color font border_radius box_shadow].freeze

  FONTS = {
    "Inter"            => "Inter — Clean modern sans",
    "DM Sans"          => "DM Sans — Geometric",
    "Manrope"          => "Manrope — Soft sans",
    "Playfair Display" => "Playfair Display — Editorial serif",
    "Lora"             => "Lora — Calligraphic serif"
  }.freeze

  RADII   = %w[none small medium large].freeze
  SHADOWS = %w[none small medium large].freeze

  HEX = /\A#(\h{3}|\h{6})\z/

  FALLBACK_STACK = %(-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif)

  def self.current
    new(Setting.get(KEY))
  end

  # Overwrites rather than merges, so a field cleared in the form is cleared
  # (Setting.set deep-merges).
  def self.save(attrs)
    record = Setting.find_or_initialize_by(key: KEY)
    data = attrs.to_h.stringify_keys.slice(*PERMITTED.map(&:to_s))
    data["logo_id"] = data["logo_id"].presence
    data["favicon_id"] = data["favicon_id"].presence
    record.data = data.compact_blank
    record.save!
    record
  end

  def initialize(data)
    @data = (data || {}).to_h.stringify_keys
  end

  def [](key) = @data[key.to_s]

  def primary_color
    color = @data["primary_color"].to_s.strip
    color if color.match?(HEX)
  end

  def font
    @data["font"].presence_in(FONTS.keys)
  end

  def google_font_url
    "https://fonts.googleapis.com/css2?family=#{ERB::Util.url_encode(font)}:wght@400;500;600;700&display=swap" if font
  end

  def customized?
    primary_color.present? || font.present?
  end

  # Unlayered, like Fizzy's own tokens in _global.css and appearance.css, so
  # it wins over them.
  def stylesheet
    declarations = []
    if (color = primary_color)
      declarations << "--color-link: #{color};"
      declarations << "--focus-ring-color: #{color};"
      declarations << "--color-card-default: #{color};"
      declarations << "--color-selected: color-mix(in oklch, #{color} 18%, var(--color-canvas));"
      declarations << "--color-selected-dark: color-mix(in oklch, #{color} 40%, var(--color-canvas));"
    end
    declarations << %(--font-sans: "#{font}", #{FALLBACK_STACK};) if font

    declarations.any? ? ":root {\n  #{declarations.join("\n  ")}\n}\n" : ""
  end
end
