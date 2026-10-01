# frozen_string_literal: true

# Content models (Page, CollectionEntry) announce their meaningful state
# changes (Event.announce), whoever or whatever made them — an editor, the
# API, the scheduler, an import. Worked out from what the save changed, so
# no path that saves a record can forget to announce it. Events:
#
#   * <kind>.published   — fired on the transition into published, or on
#                          restore from trash if the restored record is
#                          already published
#   * <kind>.unpublished — fired on the transition out of published, or
#                          when a published record is discarded (trashed)
#   * <kind>.updated     — fired when a published record changes any data
#                          *without* a status / discard transition
#   * <kind>.deleted     — fired on permanent destroy (purge), and also
#                          on discard if the record was draft/archived
#                          (since unpublished consumers still want to
#                          know the page is gone)
#
# Drafts and archives that move sideways (draft -> archived) are noise to
# consumers, so we don't emit for them.
#
# Including class must implement `webhook_kind` (returns "page" or "entry")
# and `webhook_payload` (returns a Hash describing the record).
module Announceable
  extend ActiveSupport::Concern

  included do
    after_commit :announce_saved_transition,    on: [:create, :update]
    after_commit :announce_destroyed_transition, on: :destroy
  end

  private

  def announce_saved_transition
    kind = webhook_kind
    was_create = id_previously_changed?

    if previous_changes.key?("deleted_at")
      from, to = previous_changes["deleted_at"]
      event =
        if to.present? && from.nil?
          # Just discarded.
          status == "published" ? "#{kind}.unpublished" : "#{kind}.deleted"
        elsif to.nil? && from.present?
          # Just restored.
          "#{kind}.published" if status == "published"
        end
      announce(event) if event
      return
    end

    # Always announce creation, for email subscribers and in-process
    # listeners; `<kind>.created` isn't something webhooks carry.
    announce("#{kind}.created") if was_create

    status_event =
      if previous_changes.key?("status")
        from, to = previous_changes["status"]
        if to == "published"
          "#{kind}.published"
        elsif from == "published"
          "#{kind}.unpublished"
        end
      elsif status == "published" && !was_create
        "#{kind}.updated"
      end

    announce(status_event) if status_event
  end

  def announce_destroyed_transition
    announce("#{webhook_kind}.deleted")
  end
end
