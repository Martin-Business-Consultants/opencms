# frozen_string_literal: true

# The text of a global's fields, for search (POST /api/search).
module Global::Searchable
  extend ActiveSupport::Concern

  def search_text
    BlockType.searchable_text_in(fields, data || {})
  end
end
