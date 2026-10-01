# frozen_string_literal: true

# PATCH /api/pages/:path/schema: replaces the page's field definitions (the
# shape of its frontmatter), not its content. The whole list is sent; this
# overwrites rather than merges, as the admin screen does.
class Api::Pages::SchemasController < Api::BaseController
  include PageScoped
  include SchemaParams

  enforce_authorization
  requires_capability "pages:write", only: :update

  def update
    @page.update_schema!(schema_attrs_from(:page)[:schema]["fields"])
    render "api/pages/show"
  end
end
