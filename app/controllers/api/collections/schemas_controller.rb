# frozen_string_literal: true

# PATCH /api/collections/:slug/schema — the entry shape for this collection:
# field definitions, whether entries can carry blocks, the notification
# wiring, and the Build board's column config. Replaces the field list
# wholesale; the other settings change only when they're sent.
class Api::Collections::SchemasController < Api::BaseController
  include CollectionScoped
  include SchemaParams

  enforce_authorization
  requires_capability "collections:write", only: :update

  # A body without the `collection` key is refused, like a bad schema, rather
  # than read as an empty field list.
  def update
    if params[:collection].nil?
      render json: {error: "invalid", errors: {collection: [%(is missing: send {"collection": {"fields": [...]}})]}}, status: :unprocessable_content
    else
      @collection.change_schema!(schema_attributes)
      render "api/collections/show"
    end
  end

  private

  def schema_attributes
    attrs = schema_attrs_from(:collection)
    attrs[:enable_blocks] = ActiveRecord::Type::Boolean.new.cast(params.dig(:collection, :enable_blocks)) if params[:collection].key?(:enable_blocks)

    if params[:collection].key?(:notification_events)
      attrs[:notification_events] = Array(params.dig(:collection, :notification_events)).map(&:to_s) & Collection::NOTIFICATION_EVENTS
    end
    attrs[:notification_emails] = params.dig(:collection, :notification_emails) if params[:collection].key?(:notification_emails)

    if params[:collection].key?(:build_config)
      attrs[:build_config] = Collection.normalize_build_config(deep_unwrap(params.dig(:collection, :build_config)))
    end
    attrs
  end
end
