# frozen_string_literal: true

# Bulk operations over the API address records by slug. Missing slugs are
# reported rather than skipped: a bulk change that quietly did nothing for
# half its input is worse than an error.
module Api::BulkSlugs
  private

  def bulk_slugs
    Array(params[:slugs]).map(&:to_s).reject(&:empty?)
  end

  def missing_slugs(found)
    bulk_slugs - found.map(&:slug)
  end
end
