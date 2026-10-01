# frozen_string_literal: true

# Bulk page operations over the API address pages by path. Missing paths are
# reported rather than skipped: a bulk publish that quietly did nothing for
# half its input is worse than an error.
module Api::PagePaths
  private

  # `paths`, or `slugs` for symmetry with the admin's long-standing param
  # name. Values are full paths either way.
  def bulk_paths
    Array(params[:paths].presence || params[:slugs]).map(&:to_s).reject(&:empty?)
  end

  def missing_paths(found)
    bulk_paths - found.map(&:path)
  end
end
