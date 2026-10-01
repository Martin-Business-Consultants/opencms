# frozen_string_literal: true

# An entry's category (one) and tags (many), each an entry of the pool
# collection its own collection names (`categories_collection`,
# `tags_collection`). A collection with no pool can't categorize or tag.
module CollectionEntry::Taxonomized
  extend ActiveSupport::Concern

  included do
    belongs_to :category,
               class_name:  "CollectionEntry",
               foreign_key: :category_entry_id,
               optional:    true
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :tags, through: :taggings, source: :tag_entry
  end

  def category_pool
    collection&.categories_collection
  end

  def tag_pool
    collection&.tags_collection
  end

  private

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
