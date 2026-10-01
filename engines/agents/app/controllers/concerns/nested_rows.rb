# frozen_string_literal: true

# Rows added in the browser (the schema-editor controller) are keyed by an
# opaque id ("n1k2…"), and strong parameters only permit a nested-attributes
# hash keyed by numbers. Listing the rows first keeps them: nested attributes
# take a list as happily as a hash.
module NestedRows
  private

  def listing_rows(params, *names)
    names.each do |name|
      rows = params[name]
      params[name] = rows.keys.map { rows[it] } if rows.respond_to?(:keys)
    end
    params
  end
end
