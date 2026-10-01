# frozen_string_literal: true

# The Build board: two columns standing for one boolean field, which dragging
# a card across writes (CollectionEntry::Boardable). What the board means is
# `build_config`; everything here reads it forgivingly, because a field can be
# renamed or dropped long after the board was set up.
module Collection::Boarded
  extend ActiveSupport::Concern

  # Types a Build card can edit in place. Everything here renders as a single
  # control that fits on a card and writes one scalar — no repeaters, no
  # asset pickers, nothing that needs the full entry form.
  BUILD_INLINE_TYPES = %w[boolean select string integer url datetime].freeze

  class_methods do
    # Squeeze a posted Build config into the shape #validate_build_config reads:
    # the field the columns stand for, optional column labels, the fields a card
    # edits inline, and whatever else the right-hand column turns on with it. No
    # field means the board is off, and an off board carries nothing else —
    # that's how the schema form switches it back off.
    #
    # "Nothing extra" is the default, so an empty `also_fields` and a false
    # `also_publish` are dropped rather than stored: a board that only flips its
    # one field reads back exactly as it did before there was anything else to
    # carry.
    def normalize_build_config(raw)
      return {} unless raw.is_a?(Hash)

      field = raw["field"].to_s.strip
      return {} if field.empty?

      {
        "field"        => field,
        "off_label"    => raw["off_label"].to_s.strip.presence,
        "on_label"     => raw["on_label"].to_s.strip.presence,
        "card_fields"  => normalize_field_names(raw["card_fields"]),
        "also_fields"  => normalize_field_names(raw["also_fields"]).presence,
        "also_publish" => (ActiveModel::Type::Boolean.new.cast(raw["also_publish"]) || nil)
      }.compact
    end

    def normalize_field_names(raw)
      Array(raw).map { |n| n.to_s.strip }.reject(&:empty?).uniq
    end
    private :normalize_field_names
  end

  # `build_config` is `{"field" => "active", "off_label" => …, "on_label" => …,
  # "card_fields" => ["day"], "also_fields" => ["featured"],
  # "also_publish" => true}`. `field` names the boolean frontmatter field the
  # two columns stand for; dragging a card across the board writes it. Nothing
  # is configured until `field` is set, and clearing it turns the board off.
  #
  # `also_fields` and `also_publish` are the rest of what the right-hand column
  # means: other booleans that follow the column field, and the entry's own
  # status. The board mirrors on the way back — a card dragged left turns them
  # all off again (status returns to draft), so a column is a complete
  # statement about its cards rather than a one-way switch.
  def build_settings
    build_config.is_a?(Hash) ? build_config : {}
  end

  # The boolean field the columns represent, or nil when the board is off.
  def build_field
    f = field(build_settings["field"])
    f if f && f["type"] == "boolean"
  end

  def build_board?
    build_field.present?
  end

  # Fields rendered as inline controls on a card in the "on" column. Silently
  # drops anything the schema no longer declares — a field can be renamed or
  # deleted long after the board was set up.
  def build_card_fields
    return [] unless build_board?

    Array(build_settings["card_fields"]).filter_map { |name|
      f = field(name)
      f if f && BUILD_INLINE_TYPES.include?(f["type"]) && f["name"] != build_field["name"]
    }
  end

  # Other boolean fields the column field drags along with it. Same forgiving
  # read as #build_card_fields: a name the schema has since dropped, or one
  # that's no longer a boolean, just stops being carried.
  def build_also_fields
    return [] unless build_board?

    Array(build_settings["also_fields"]).filter_map { |name|
      f = field(name)
      f if f && f["type"] == "boolean" && f["name"] != build_field["name"]
    }
  end

  # Whether a move across the board also publishes (right) or unpublishes
  # (left) the entry.
  def build_publishes?
    build_board? && build_settings["also_publish"].present?
  end

  # Every boolean the right-hand column turns on, in one list: the field the
  # columns stand for, then whatever else was configured to follow it.
  def build_move_fields
    return [] unless build_board?

    [build_field, *build_also_fields].uniq { |f| f["name"] }
  end

  def build_column_labels
    {
      "off" => build_settings["off_label"].presence || "Off",
      "on"  => build_settings["on_label"].presence  || "On"
    }
  end

  # The field a card may edit in place, by name, or nil.
  def inline_field(name)
    found = field(name)
    found if found && BUILD_INLINE_TYPES.include?(found["type"])
  end

  def inline_fields
    fields.select { |f| f.is_a?(Hash) && BUILD_INLINE_TYPES.include?(f["type"]) }
  end

  private

  # An unset (or emptied) config is the board switched off, not an error —
  # that is how the schema form turns it back off.
  def validate_build_config
    return errors.add(:build_config, "must be an object") unless build_config.is_a?(Hash)

    name = build_settings["field"].to_s
    card_fields = build_settings["card_fields"]
    also_fields = build_settings["also_fields"]

    if name.empty?
      if card_fields.present? || also_fields.present? || build_settings["also_publish"].present?
        errors.add(:build_config, "needs a field before the rest of the board means anything")
      end
      return
    end

    target = field(name)
    if target.nil?
      errors.add(:build_config, "field #{name} is not in this collection's schema")
    elsif target["type"] != "boolean"
      errors.add(:build_config, "field #{name} must be a boolean, not #{target["type"]}")
    end

    validate_build_card_fields(card_fields)
    validate_build_also_fields(also_fields)
  end

  def validate_build_card_fields(card_fields)
    return if card_fields.nil?
    return errors.add(:build_config, "card_fields must be an array") unless card_fields.is_a?(Array)

    card_fields.each do |card_name|
      f = field(card_name)
      if f.nil?
        errors.add(:build_config, "card field #{card_name} is not in this collection's schema")
      elsif !BUILD_INLINE_TYPES.include?(f["type"])
        errors.add(:build_config, "card field #{card_name} is a #{f["type"]}, which cannot be edited on a card")
      end
    end
  end

  # Anything carried across with the column field has to be a boolean for the
  # same reason the column field does: two columns are two states.
  def validate_build_also_fields(also_fields)
    return if also_fields.nil?
    return errors.add(:build_config, "also_fields must be an array") unless also_fields.is_a?(Array)

    also_fields.each do |also_name|
      f = field(also_name)
      if f.nil?
        errors.add(:build_config, "field #{also_name} is not in this collection's schema")
      elsif f["type"] != "boolean"
        errors.add(:build_config, "field #{also_name} must be a boolean to move with the columns, not #{f["type"]}")
      end
    end
  end
end
