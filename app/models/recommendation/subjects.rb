# frozen_string_literal: true

# What a finding is about, found the way agents name things: by path or
# collection and slug, not database id. An agent that has just read /pricing
# shouldn't have to look up a number to say something about it. Not finding
# one isn't an error: a finding about a page that doesn't exist yet (the whole
# point of a content gap) simply has no subject.
module Recommendation::Subjects
  extend ActiveSupport::Concern

  class_methods do
    def find_subject(type: nil, id: nil, path: nil, collection: nil, slug: nil)
      case type.to_s
      when "Page"
        id.present? ? Page.find_by(id: id) : Page.find_by(path: path)
      when "CollectionEntry"
        find_entry_subject(id: id, collection: collection, slug: slug)
      end
    end

    private

    def find_entry_subject(id:, collection:, slug:)
      return CollectionEntry.find_by(id: id) if id.present?

      Collection.find_by(slug: collection)&.entries&.find_by(slug: slug)
    end
  end
end
