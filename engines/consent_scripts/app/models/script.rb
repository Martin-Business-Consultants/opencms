# frozen_string_literal: true

# A third-party tag the public site loads, filed under a consent category.
#
# The category is what the consent banner asks about, so it is the one field
# that has to be right: a pixel filed under "necessary" would load before
# anyone agreed to it. Everything else — where it goes, whether it's a file
# or a snippet — is plumbing the embed (`/consent.js`) takes care of.
class Script < ApplicationRecord
  include Eventable

  # In the order the banner presents them. `necessary` never waits for
  # consent; the other three each get a toggle.
  CATEGORIES = %w[necessary functional analytics marketing].freeze

  CATEGORY_LABELS = {
    "necessary"  => "Necessary",
    "functional" => "Functional",
    "analytics"  => "Analytics",
    "marketing"  => "Marketing"
  }.freeze

  CATEGORY_DESCRIPTIONS = {
    "necessary"  => "Required for the site to work. Always on — never wait on a visitor's choice.",
    "functional" => "Remembers choices and powers features like chat or embedded video.",
    "analytics"  => "Measures how the site is used, in aggregate.",
    "marketing"  => "Builds a profile of the visitor to show them relevant ads elsewhere."
  }.freeze

  PLACEMENTS = %w[head body_start body_end].freeze

  PLACEMENT_LABELS = {
    "head"       => "In <head>",
    "body_start" => "Start of <body>",
    "body_end"   => "End of <body>"
  }.freeze

  validates :name,      presence: true
  validates :category,  inclusion: {in: CATEGORIES}
  validates :placement, inclusion: {in: PLACEMENTS}
  validates :src, format: {with: %r{\Ahttps?://\S+\z}, message: "must be an http(s) URL"}, allow_nil: true
  validate  :src_or_code

  normalizes :name,   with: ->(v) { v.to_s.strip }
  normalizes :vendor, with: ->(v) { v.to_s.strip.presence }
  normalizes :src,    with: ->(v) { v.to_s.strip.presence }
  normalizes :code,   with: ->(v) { v.to_s.strip.presence }

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql(CATEGORIES.each_with_index.map { |c, i| "WHEN category = #{connection.quote(c)} THEN #{i}" }.then { |w| "CASE #{w.join(" ")} ELSE 99 END" }), :name) }

  def necessary? = category == "necessary"

  # The shape the embed and the build-facing API send to the browser. No
  # notes, no timestamps — only what is needed to load it.
  def as_embed
    {
      id:        id,
      name:      name,
      category:  category,
      placement: placement,
      src:       src,
      code:      code,
      async:     async,
      defer:     defer
    }
  end

  private

  def src_or_code
    return if src.present? || code.present?

    errors.add(:base, "Add a script URL, inline code, or both.")
  end
end
