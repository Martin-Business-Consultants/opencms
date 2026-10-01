# frozen_string_literal: true

# What the page, entry and global forms share: reading the content form back
# (ContentForm) and saving it — or, when the record is live and the user
# can't publish it, filing the change as a revision for review through the
# record's own gate (Revisable), as the API's GatedWrites does. Drafts save directly, except that publishing
# one (or scheduling it) without the publish capability is held back and
# becomes a review request (PublicationGate), as in the API.
module ContentEditing
  extend ActiveSupport::Concern

  included do
    helper_method :can_publish_content?
  end

  private

  def content_block_types
    @content_block_types ||= BlockType.all.index_by(&:slug)
  end

  # An object of schema fields from params[scope][key], or `original` when
  # the form didn't post it.
  def decoded_content_object(scope, key, fields, original)
    raw = params.dig(scope, key)
    return original if raw.nil?

    ContentForm.object(fields, raw, original: original, block_types: content_block_types)
  end

  def decoded_content_blocks(scope, original)
    raw = params.dig(scope, :blocks)
    return original if raw.nil?

    ContentForm.blocks(raw, block_types: content_block_types)
  end

  # Checkbox lists post a leading "" so an emptied list still arrives.
  def content_ids(scope, key)
    ids = params.dig(scope, key)
    ids.nil? ? nil : Array(ids).compact_blank.map(&:to_i)
  end

  def content_time(scope, key)
    value = params.dig(scope, key)
    value.nil? ? :absent : value.presence
  end

  # :saved, :invalid, :unchanged, [:proposed | :conflict, revision], or
  # [:publication_requested, review_request] (the rest of the write saved).
  def save_content(record, attributes, prefix:)
    return propose_content_revision(record, attributes) if content_review_gated?(record, prefix)

    record.assign_attributes(attributes)
    held = withhold_content_publication(record, prefix)
    if held.any? && !record.changed?
      [:publication_requested, ReviewRequest.request_publication(record, by: Current.user)]
    elsif record.save
      held.any? ? [:publication_requested, ReviewRequest.request_publication(record, by: Current.user)] : :saved
    else
      :invalid
    end
  end

  # Whether save_content wrote the record, so the caller records the update.
  def content_saved?(outcome, record)
    outcome == :saved || (outcome in [:publication_requested, _]) && record.previous_changes.any?
  end

  # What would publish a draft or a new record, taken back when the user
  # can't publish (PublicationGate); [] when they can.
  def withhold_content_publication(record, prefix)
    can_publish_content?(prefix) ? [] : PublicationGate.withhold(record)
  end

  def can_publish_content?(prefix)
    Current.user&.can?("#{prefix}:publish")
  end

  # A record in front of visitors (Revisable): a published page or entry, or
  # any global (they have no draft state).
  def content_review_gated?(record, prefix)
    record.review_gated?(can_publish: can_publish_content?(prefix))
  end

  def propose_content_revision(record, attributes)
    proposal = record.propose(attributes, by: Current.user, source: "ui", note: params[:review_note].presence)

    case proposal.outcome
    when :proposed, :conflict then [proposal.outcome, proposal.revision]
    else proposal.outcome
    end
  end

  # Redirects for the outcomes that don't re-render the form.
  def after_content_save(outcome, edit_path, saved:)
    case outcome
    in :saved then redirect_to edit_path, notice: saved
    in :unchanged then redirect_to edit_path, notice: "No changes to send for review."
    in [:proposed, revision]
      flash[:review_revision_id] = revision.id
      redirect_to edit_path, notice: "Saved as a revision for review — the live content is unchanged."
    in [:conflict, revision]
      flash[:review_revision_id] = revision.id
      redirect_to edit_path, alert: "A revision is already waiting for review. It needs a decision before another can be filed."
    in [:publication_requested, _request]
      redirect_to edit_path, notice: "Saved as a draft. Publishing it is waiting for review."
    end
  end
end
