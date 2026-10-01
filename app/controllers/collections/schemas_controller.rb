# frozen_string_literal: true

# A collection's shape: its fields, whether entries take blocks, the Build
# board, and who's emailed on entry events.
class Collections::SchemasController < ApplicationController
  include CollectionScoped

  requires_capability "collections:write", only: [:show, :update]

  def show
  end

  def update
    if @collection.change_schema(schema_attributes)
      redirect_to collection_schema_path(@collection.slug), notice: "Schema saved"
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def schema_attributes
    raw = params.require(:collection)
    attributes = {
      schema: {"fields" => SchemaFields.from_params(raw[:fields])},
      enable_blocks: ActiveRecord::Type::Boolean.new.cast(raw[:enable_blocks]) || false,
      notification_events: Array(raw[:notification_events]).map(&:to_s) & Collection::NOTIFICATION_EVENTS,
      notification_emails: raw[:notification_emails]
    }
    # Absent means "not this form's business", not "switch the board off" —
    # only a posted config replaces the stored one.
    if raw[:build_config]
      attributes[:build_config] = Collection.normalize_build_config(raw[:build_config].to_unsafe_h)
    end
    attributes
  end
end
