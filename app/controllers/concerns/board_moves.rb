# frozen_string_literal: true

# What the Build board may do for this person. A board that publishes is a
# publishing tool, so someone without that capability gets a readable board
# they can't drag, rather than a drag that always fails. Flipping frontmatter
# is an ordinary `entries:write` edit.
module BoardMoves
  extend ActiveSupport::Concern

  included do
    helper_method :can_move_cards?
  end

  private

  def can_move_cards?
    return false unless granted?("entries:write")
    return true unless @collection.build_publishes?

    granted?("entries:publish").present?
  end
end
