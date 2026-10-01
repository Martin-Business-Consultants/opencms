# frozen_string_literal: true

# The Build board: two columns standing for one boolean frontmatter field, so
# moving a card between them IS the edit. Which field, and which other fields
# stay editable on a card, is per-collection configuration (the schema page) —
# without it there is no board to render, so send the editor where it's chosen.
class Collections::BoardsController < ApplicationController
  include CollectionScoped, BoardMoves

  requires_capability "entries:read", only: :show

  def show
    if @collection.build_board?
      @entries = @collection.entries.order(:title).to_a
    else
      redirect_to collection_schema_path(@collection.slug), notice: "Choose the field the Build board’s columns stand for."
    end
  end
end
