# frozen_string_literal: true

# PATCH /api/globals/:slug/schema — the field definitions that shape a
# global's `data`. Replaces the field list wholesale.
class Api::Globals::SchemasController < Api::BaseController
  include GlobalScoped
  include SchemaParams

  enforce_authorization
  requires_capability "globals:write", only: :update

  def update
    @global.update_schema!(schema_attrs_from(:global)[:schema]["fields"])
    render "api/globals/show"
  end
end
