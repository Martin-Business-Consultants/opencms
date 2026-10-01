# frozen_string_literal: true

# A page's category (one) and tags (many), each an entry of a well-known pool
# collection: "page-categories" and "page-tags". Collections point at their
# pools through ids; pages don't need that indirection, since one shared pool
# per side is enough.
module Page::Taxonomized
  extend ActiveSupport::Concern

  PAGE_CATEGORIES_SLUG = "page-categories"
  PAGE_TAGS_SLUG = "page-tags"

  included do
    belongs_to :category, class_name: "CollectionEntry", foreign_key: :category_entry_id, optional: true
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :tags, through: :taggings, source: :tag_entry
  end

  def category_pool
    Collection.find_by(slug: PAGE_CATEGORIES_SLUG)
  end

  def tag_pool
    Collection.find_by(slug: PAGE_TAGS_SLUG)
  end

  private

  # With no pool collection a page can't be categorized; refusing stops an
  # editor quietly assigning into a pool that doesn't exist.
  def validate_category_in_pool
    PageValidator.validate_category_in_pool(category_entry_id, category, category_pool).each do |msg|
      errors.add(:category, msg)
    end
  end

  def validate_tags_in_pool
    PageValidator.validate_tags_in_pool(taggings, tags, tag_pool).each do |msg|
      errors.add(:tags, msg)
    end
  end
end
