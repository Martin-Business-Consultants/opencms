# frozen_string_literal: true

# A control on a Build board card: a select, text, number, date or yes/no the
# collection puts on its cards (a special's day of the week, say). Still one
# key merged into the frontmatter, and only fields the schema declares whose
# type fits on a card — the schema decides, not the board's own card_fields,
# so reconfiguring the board can't widen what an open page may write.
class Collections::Entries::CardFieldsController < ApplicationController
  include EntryScoped

  requires_capability "entries:write", only: :update

  def update
    field = @collection.inline_field(params[:field])

    if field.nil?
      redirect_to build_collection_entries_path(@collection.slug), alert: "#{params[:field]} can’t be edited from the board."
    elsif @entry.set_field(field["name"], value_for(field))
      redirect_to build_collection_entries_path(@collection.slug), notice: "#{helpers.field_label_text(field)} updated for #{@entry.title}"
    else
      redirect_to build_collection_entries_path(@collection.slug), alert: @entry.errors.full_messages.to_sentence
    end
  end

  private

  # Params arrive as strings. Coerce through the schema's own walker, and read
  # a blank as "clear this field" — except a boolean, where false is a value.
  # A date comes from a datetime-local input (wall-clock time, no zone) and is
  # stored as ISO 8601 in UTC, as the entry form stores it.
  def value_for(field)
    raw = params[:value]
    if field["type"] == "boolean"
      ActiveModel::Type::Boolean.new.cast(raw) == true
    elsif raw.to_s.strip.empty?
      nil
    elsif field["type"] == "datetime"
      Time.zone.parse(raw.to_s)&.utc&.iso8601(3) || raw.to_s
    else
      BlockType::Validator.coerce_data([field], {field["name"] => raw})[field["name"]]
    end
  end
end
