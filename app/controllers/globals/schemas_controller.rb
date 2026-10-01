# frozen_string_literal: true

# A global's fields, edited with the schema editor.
class Globals::SchemasController < ApplicationController
  include GlobalScoped

  requires_capability "globals:write", only: [:show, :update]

  def show
  end

  def update
    if @global.update_schema(SchemaFields.from_params(params.dig(:global, :fields)))
      redirect_to global_schema_path(@global.slug), notice: "Schema saved"
    else
      render :show, status: :unprocessable_content
    end
  end
end
