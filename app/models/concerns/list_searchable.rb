# frozen_string_literal: true

# A list screen's search (WordPress's ?s=): `search_on :title, :slug` gives the
# model `search_list(term)`, rows whose named columns contain the term, case
# folded as SQLite's LIKE does. A blank term matches everything, so a list can
# always call it.
module ListSearchable
  extend ActiveSupport::Concern

  class_methods do
    def search_on(*columns)
      scope :search_list, ->(term) {
        text = term.to_s.strip
        if text.empty?
          all
        else
          pattern = "%#{sanitize_sql_like(text)}%"
          where(columns.map { |column| arel_table[column].matches(pattern, "\\") }.reduce(:or))
        end
      }
    end
  end
end
