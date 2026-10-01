# frozen_string_literal: true

module BoardsHelper
  # What a move across the Build board carries, said before anyone drags —
  # a board can turn on more than its one field, and a drag that quietly
  # publishes is not something to leave the editor to discover.
  def board_move_description(collection)
    labels = collection.build_column_labels
    names = collection.build_move_fields.map { field_label_text(it) }.to_sentence
    right = collection.build_publishes? ? "turns on #{names} and publishes the entry" : "turns on #{names}"
    left = collection.build_publishes? ? "turns them off and returns it to draft" : "turns them off"
    "Dragging a card to #{labels["on"]} #{right}. Dragging it back to #{labels["off"]} #{left}."
  end

  # A stored ISO 8601 time as a datetime-local input wants it.
  def datetime_local_value(value)
    return "" if value.blank?

    Time.zone.parse(value.to_s)&.strftime("%Y-%m-%dT%H:%M").to_s
  rescue ArgumentError
    ""
  end
end
