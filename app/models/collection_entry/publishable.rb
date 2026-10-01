# frozen_string_literal: true

# An entry's status and its schedule, as for pages (Page::Publishable): a
# publish_at or unpublish_at time takes effect once it has passed. Changing
# status is an ordinary save, so Announceable announces the transition either
# way.
module CollectionEntry::Publishable
  extend ActiveSupport::Concern

  included do
    scope :due_to_publish, ->(now = Time.current) {
      where("publish_at IS NOT NULL AND publish_at <= ? AND status != 'published'", now)
    }
    scope :due_to_unpublish, ->(now = Time.current) {
      where("unpublish_at IS NOT NULL AND unpublish_at <= ? AND status = 'published'", now)
    }
  end

  class_methods do
    def publish_due(now = Time.current)
      due_to_publish(now).find_each { it.publish_on_schedule(now) }
    end

    def unpublish_due(now = Time.current)
      due_to_unpublish(now).find_each(&:unpublish_on_schedule)
    end

    # Sets every entry of `collection` to `to`, all or nothing, and records one
    # event naming them. One save per entry (not update_all) so each fires the
    # webhook and debounced deploy a single edit does.
    def change_status_of(entries, to:, collection:)
      transaction { entries.each { |entry| entry.update!(status: to) unless entry.status == to } }
      track_event(:bulk_status_changed, collection: collection.slug, to: to, count: entries.size, slugs: entries.map(&:slug)) if entries.any?
      entries
    end
  end

  def scheduled?
    (publish_at.present? && publish_at > Time.current && status != "published") ||
      (unpublish_at.present? && unpublish_at > Time.current && status == "published")
  end

  def publish_on_schedule(now = Time.current)
    update!(status: "published", published_at: published_at || now, publish_at: nil)
  end

  def unpublish_on_schedule
    update!(status: "archived", unpublish_at: nil)
  end

  def track_creation
    track_event(:created, collection: collection.slug, slug: slug, status: status)
  end

  # What an edit did to the entry's status, in the audit vocabulary the entry
  # form, bulk status changes and a publishing Build board all speak:
  # entry.published when it went live, entry.unpublished when it came down,
  # entry.updated otherwise. `details` are the screen's own particulars (the
  # board's fields and column).
  def track_update(from:, **details)
    base = {collection: collection.slug, slug: slug}.merge(details)
    if status == from
      track_event(:updated, **base, status: status)
    elsif status == "published"
      track_event(:published, **base.merge(from: from))
    elsif from == "published"
      track_event(:unpublished, **base.merge(to: status))
    else
      track_event(:updated, **base.merge(from: from, to: status))
    end
  end
end
