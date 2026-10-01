# frozen_string_literal: true

# PATCH /api/collections/:collection/entries/:slug/update_field — the flag
# widened past booleans: merges one scalar frontmatter key, for the fields a
# Build card can edit in place (Collection::BUILD_INLINE_TYPES). A blank value
# clears the key rather than leaving an empty string in the JSON the site reads.
class Api::Collections::Entries::CardFieldsController < Api::BaseController
  include EntryScoped

  enforce_authorization
  requires_capability "entries:write", only: :update

  def update
    field = @collection.inline_field(params[:field])

    if field
      @entry.set_field!(field["name"], value_for(field))
      render "api/collection_entries/show"
    else
      render json: {error: "invalid", message: "#{params[:field].inspect} is not an inline-editable field on #{@collection.slug}",
                    inline_fields: @collection.inline_fields.map { it["name"] }},
        status: :unprocessable_content
    end
  end

  private

  # A wall-clock time with no zone, as a datetime-local input sends it.
  LOCAL_DATETIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?\z/

  def value_for(field)
    raw = params[:value]
    return ActiveModel::Type::Boolean.new.cast(raw) if field["type"] == "boolean"
    return nil if raw.nil? || raw.to_s.strip.empty?
    return local_datetime(raw) if field["type"] == "datetime" && raw.to_s.match?(LOCAL_DATETIME)

    BlockType::Validator.coerce_data([field], {field["name"] => raw})[field["name"]]
  end

  # Read in the site's zone (Site.time_zone: Settings › General, else the
  # server's), as the admin board reads it, and stored as ISO 8601 UTC, the
  # shape an ISO value with a zone is stored in.
  def local_datetime(raw)
    Site.time_zone.parse(raw.to_s).utc.iso8601
  end
end
