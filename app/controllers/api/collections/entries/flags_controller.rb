# frozen_string_literal: true

# PATCH /api/collections/:collection/entries/:slug/toggle_field — flips one
# boolean frontmatter field, merging the single key instead of replacing the
# whole frontmatter the way PATCH does, so a caller toggling `featured` on 40
# entries can't clobber the other fields through a read-modify-write race.
class Api::Collections::Entries::FlagsController < Api::BaseController
  include EntryScoped

  enforce_authorization
  requires_capability "entries:write", only: :update

  def update
    field = @collection.boolean_field(params[:field])

    if field && !params.key?(:value)
      # A switch is on or off; without a value there's nothing to store (it
      # used to be stored as null).
      render json: {error: "invalid", message: "value is required: true or false"}, status: :unprocessable_content
    elsif field
      @entry.set_field!(field["name"], ActiveModel::Type::Boolean.new.cast(params[:value]), keep_nil: true)
      render "api/collection_entries/show"
    else
      render json: {error: "invalid", message: "#{params[:field].inspect} is not a boolean field on #{@collection.slug}",
                    boolean_fields: @collection.boolean_fields.map { it["name"] }},
        status: :unprocessable_content
    end
  end
end
