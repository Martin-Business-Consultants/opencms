# frozen_string_literal: true

# A card dropped into a Build board column (`column=on|off`). The column field
# is the point of it, but a board can carry more across — other booleans, and
# the entry's own published status — so one drop is one save of everything the
# column stands for, and a card never comes to rest half-moved. Answers the
# board's drag-and-drop with a morph of the board; a plain form post gets the
# board back.
class Collections::Entries::PlacementsController < ApplicationController
  include EntryScoped, BoardMoves

  requires_capability "entries:write", only: :create

  def create
    kind, message = place(params[:column] == "on")

    respond_to do |format|
      format.turbo_stream do
        flash.now[kind] = message
        render_board
      end
      format.html { redirect_to build_collection_entries_path(@collection.slug), kind => message }
    end
  end

  private

  # [:notice or :alert, what to tell the person]
  def place(on)
    if !@collection.build_board?
      [:alert, "This collection has no Build board."]
    elsif !can_move_cards?
      [:alert, "Moving a card here publishes it, which needs publish access."]
    else
      if @entry.place_on_board(on)
        [:notice, "#{@entry.title} moved to #{@collection.build_column_labels[on ? "on" : "off"]}"]
      else
        [:alert, @entry.errors.full_messages.to_sentence]
      end
    end
  end

  def render_board
    render turbo_stream: [
      turbo_stream.replace("build_board", partial: "collections/boards/board", method: :morph,
        locals: {collection: @collection, entries: @collection.entries.order(:title).to_a, can_move: can_move_cards?}),
      turbo_stream.replace("flash", partial: "layouts/shared/flash")
    ]
  end
end
