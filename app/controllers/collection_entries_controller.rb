# frozen_string_literal: true

# A collection's entries: the table, an entry's form (its settings, fields,
# blocks when the collection has them, body and SEO), and delete. Bulk
# changes, the table's yes/no switches and the Build board's writes are
# resources under Collections::Entries. A published entry edited by someone
# who can't publish is filed as a revision for review (ContentEditing).
class CollectionEntriesController < ApplicationController
  include CollectionScoped
  include ContentEditing

  requires_capability "entries:read",   only: :index
  requires_capability "entries:write",  only: [:new, :create, :edit, :update]
  requires_capability "entries:delete", only: :destroy

  before_action :set_entry, only: [:edit, :update, :destroy]

  def index
    @status = params[:status].presence_in(CollectionEntry::STATUSES)
    @flag_fields = @collection.fields.select { it["type"] == "boolean" }
    @status_counts = @collection.entries.group(:status).count
    entries = @collection.entries.order(updated_at: :desc).search_list(search_term)
    entries = entries.where(status: @status) if @status
    @entries = paginate(entries)
  end

  def new
    @entry = @collection.entries.new(status: "draft", locale: "en", frontmatter: {}, blocks: [], seo: {}, body_markdown: "")
  end

  def create
    @entry = @collection.entries.new
    @entry.assign_attributes(entry_attributes(@entry))
    @entry.slug = @entry.title.to_s.parameterize if @entry.slug.blank?
    held = withhold_content_publication(@entry, "entries")

    if @entry.save
      @entry.track_creation
      notice = "Entry created"
      if held.any?
        ReviewRequest.request_publication(@entry, by: Current.user)
        notice += " as a draft. Publishing it is waiting for review."
      end
      redirect_to edit_collection_entry_path(@collection.slug, @entry.slug), notice: notice
    else
      render :new, status: :unprocessable_content
    end
  rescue ContentForm::InvalidJson => e
    invalid_json(e, :new)
  end

  def edit
  end

  def update
    prior_status = @entry.status
    outcome = save_content(@entry, entry_attributes(@entry), prefix: "entries")

    if outcome == :invalid
      render :edit, status: :unprocessable_content
    else
      @entry.track_update(from: prior_status) if content_saved?(outcome, @entry)
      after_content_save(outcome, edit_collection_entry_path(@collection.slug, @entry.slug), saved: "Entry saved")
    end
  rescue ContentForm::InvalidJson => e
    invalid_json(e, :edit)
  end

  def destroy
    @entry.trash
    redirect_to collection_entries_path(@collection.slug), notice: "Entry moved to trash"
  end

  private

  def set_entry
    @entry = @collection.entries.find_by!(slug: params[:slug])
  end

  def entry_attributes(entry)
    attributes = params.require(:entry).permit(:slug, :title, :status, :locale, :category_entry_id, :body_markdown).to_h
    # A textarea posts CRLF; the body is stored with LF, so an untouched body
    # isn't a change (nor, on a live entry, a revision).
    attributes["body_markdown"] = attributes["body_markdown"].gsub("\r\n", "\n") if attributes["body_markdown"].is_a?(String)
    tag_ids = content_ids(:entry, :tag_ids)
    attributes["tag_ids"] = tag_ids unless tag_ids.nil?
    %i[publish_at unpublish_at].each do |key|
      value = content_time(:entry, key)
      attributes[key.to_s] = value unless value == :absent
    end
    attributes["frontmatter"] = decoded_content_object(:entry, :frontmatter, @collection.fields, entry.frontmatter)
    attributes["blocks"] = decoded_content_blocks(:entry, entry.blocks) if @collection.enable_blocks?
    attributes["seo"] = decoded_content_object(:entry, :seo, SeoFields::ALL, entry.seo)
    attributes
  end

  def invalid_json(error, template)
    @invalid_json = {error.path => params.dig(:entry, :seo, :json_ld).to_s}
    @entry.valid?
    @entry.errors.add(:seo, error.message)
    render template, status: :unprocessable_content
  end
end
