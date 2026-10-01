# frozen_string_literal: true

# A yes/no field flipped from the entries table, without opening the entry.
# Deliberately narrow: the field must be declared `boolean` in the schema, and
# the value is merged into the frontmatter (CollectionEntry::Boardable).
class Collections::Entries::FlagsController < ApplicationController
  include EntryScoped

  requires_capability "entries:write", only: :update

  def update
    field = @collection.boolean_field(params[:field])
    value = ActiveModel::Type::Boolean.new.cast(params[:value]) == true

    if field.nil?
      redirect_back_or_to collection_entries_path(@collection.slug), alert: "Unknown yes/no field."
    elsif @entry.set_field(field["name"], value)
      redirect_back_or_to collection_entries_path(@collection.slug),
        notice: "#{helpers.field_label_text(field)} #{value ? "on" : "off"} for #{@entry.title}"
    else
      redirect_back_or_to collection_entries_path(@collection.slug), alert: @entry.errors.full_messages.to_sentence
    end
  end
end
