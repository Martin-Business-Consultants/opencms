# frozen_string_literal: true

# Pages form a tree. A page's `slug` is one path segment; its `path` is its
# parent's path plus the slug, denormalized with `depth` so reads never walk
# the tree. Moving or renaming a page rewrites its descendants' paths, and
# trashing a page trashes its children with it.
module Page::Treeable
  extend ActiveSupport::Concern

  included do
    belongs_to :parent, class_name: "Page", optional: true
    has_many :children, class_name: "Page", foreign_key: :parent_id, dependent: :destroy

    before_validation :compute_path_and_depth

    after_save :resync_descendants_paths, if: :saved_change_to_path?
  end

  # URLs (admin and public) address pages by full path, not leaf slug.
  def to_param
    path
  end

  # Walk to the root, oldest ancestor first.
  def ancestors
    chain = []
    node = parent
    while node
      chain.unshift(node)
      node = node.parent
    end
    chain
  end

  # All descendants in breadth-first order. Bounded depth to defend against
  # accidental cycles even though a validation prevents them. Read from the
  # database rather than the `children` association, which can be a stale
  # empty cache on a page loaded before its children existed (see #discard!),
  # and a rename would then leave its descendants' paths behind.
  def descendants(max_depth: 32)
    out = []
    queue = Page.where(parent_id: id).to_a
    visited = 0
    while (node = queue.shift)
      visited += 1
      break if visited > 10_000

      out << node
      next if node.depth >= max_depth

      queue.concat(Page.where(parent_id: node.id).to_a)
    end
    out
  end

  # Trashing cascades to direct children, or their paths would point at a
  # hidden parent and the tree would show gaps.
  #
  # `Page.where(parent_id: id)` rather than `children`: Rails' inverse
  # association handling sometimes preloads `children` as empty when the
  # parent was created before the child, which would hide siblings from the
  # cascade.
  def discard!
    return self if discarded?

    transaction do
      Page.where(parent_id: id).find_each(&:discard!)
      super
    end
  end

  private

  # Recompute path = parent.path + "/" + slug; depth = parent.depth + 1.
  # Runs in before_validation so uniqueness checks see the new path.
  def compute_path_and_depth
    return if slug.blank?

    result = PageValidator.compute_path_and_depth(parent_id, slug)
    self.path = result[:path]
    self.depth = result[:depth]
  end

  # Reject self-as-parent and any descendant-as-parent (would create a cycle).
  def validate_parent_not_self_or_descendant
    PageValidator.validate_parent_not_self_or_descendant(id, parent_id, persisted?).each do |msg|
      errors.add(:parent_id, msg)
    end
  end

  # When a page's path changes (its slug or parent changed), every
  # descendant's stored path is stale. Re-walk and update them in one pass,
  # with bare SQL: a descendant doesn't need a version snapshot or a search
  # resync because its parent moved.
  def resync_descendants_paths
    descendants.each do |child|
      new_parent_path = (child.parent_id == id) ? path : child.parent&.path
      next unless new_parent_path

      new_path = "#{new_parent_path}/#{child.slug}"
      new_depth = (child.parent&.depth || -1) + 1
      next if child.path == new_path && child.depth == new_depth

      Page.where(id: child.id).update_all(path: new_path, depth: new_depth, updated_at: Time.current)
      # Mirror the update in memory so later iterations compute their own
      # children's paths from it.
      child.assign_attributes(path: new_path, depth: new_depth)
    end
  end
end
