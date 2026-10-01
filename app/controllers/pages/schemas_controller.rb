# frozen_string_literal: true

# A page's own fields (frontmatter), edited with the schema editor.
class Pages::SchemasController < ApplicationController
  requires_capability "pages:write", only: [:show, :update]

  include PageScoped

  def show
  end

  def update
    if @page.update_schema(SchemaFields.from_params(params.dig(:page, :fields)))
      redirect_to page_schema_path(@page.path), notice: "Schema saved"
    else
      render :show, status: :unprocessable_content
    end
  end
end
