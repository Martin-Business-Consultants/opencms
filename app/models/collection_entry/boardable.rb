# frozen_string_literal: true

# One-key frontmatter writes: a boolean flipped from the entries table, a card
# control on the Build board, and a card dropped into a board column. Unlike
# the entry form, which posts the whole frontmatter blob, these MERGE into it,
# so an entry's other fields are never touched.
module CollectionEntry::Boardable
  extend ActiveSupport::Concern

  # Frontmatter is free-form JSON, so a boolean may be stored as true or as a
  # string like "false" (imports, hand-edited API writes). Read it the same way
  # everywhere so a switch can't show ON for a stored "false".
  def flag?(name)
    ActiveModel::Type::Boolean.new.cast(frontmatter_hash[name]) == true
  end

  # What a board card shows for one of its fields.
  def board_value(field)
    field["type"] == "boolean" ? flag?(field["name"]) : frontmatter_hash[field["name"]]
  end

  # Merge one key and save. nil removes the key rather than parking an empty
  # value in the JSON the site reads, unless `keep_nil` says the caller means
  # a stored null.
  def write_field(name, value, keep_nil: false)
    fields = frontmatter_hash.dup
    if value.nil? && !keep_nil
      fields.delete(name)
    else
      fields[name] = value
    end
    self.frontmatter = fields
    save
  end

  # One key written and recorded: a yes/no flipped from the entries table, a
  # card control, an API caller merging a single field. Returns whether it
  # saved.
  def set_field(name, value, keep_nil: false)
    write_field(name, value, keep_nil: keep_nil).tap { |saved| track_field_change(name, value) if saved }
  end

  def set_field!(name, value, keep_nil: false)
    set_field(name, value, keep_nil: keep_nil) || raise(ActiveRecord::RecordInvalid, self)
  end

  # Everything a board column stands for, written in one save: the column
  # field, the booleans configured to follow it, and — when the board
  # publishes — the status. Mirrored, so the left column really is "off".
  # Returns the names written, or false when the save fails.
  def move_on_board(on)
    names = collection.build_move_fields.map { it["name"] }
    fields = frontmatter_hash.dup
    names.each { fields[it] = on }
    self.frontmatter = fields
    self.status = (on ? "published" : "draft") if collection.build_publishes?
    save && names
  end

  # A card dropped into a board column, from the admin or the API, recorded in
  # the entry form's vocabulary (a move across the published line is a
  # publish) with the board's own detail alongside. Returns the names written,
  # or false.
  def place_on_board(on)
    was = status
    names = move_on_board(on)
    track_update(from: was, fields: names, to: on) if names
    names
  end

  def place_on_board!(on)
    place_on_board(on) || raise(ActiveRecord::RecordInvalid, self)
  end

  private

  def track_field_change(name, value)
    track_event(:updated, collection: collection.slug, slug: slug, field: name, to: value, status: status)
  end

  def frontmatter_hash
    frontmatter.is_a?(Hash) ? frontmatter : {}
  end
end
