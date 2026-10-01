# frozen_string_literal: true

# GET /content_blocks/new?type=hero&scope=page[blocks]&depth=1 — one new block
# row for a content form's "Add block" picker: a fresh id, the type's current
# version and its defaults, named to join the list at `scope`.
class ContentBlocksController < ApplicationController
  WRITE_CAPABILITIES = %w[pages:write entries:write globals:write].freeze
  SCOPE = /\A[a-z_]+(\[[A-Za-z0-9_]+\])*\z/

  skip_authorization
  before_action :require_content_write

  def new
    block_type = BlockType.find_by!(slug: params[:type].to_s)
    scope = params[:scope].to_s
    return head(:bad_request) unless scope.match?(SCOPE)

    block = {"id" => SecureRandom.uuid, "type" => block_type.slug, "version" => block_type.version,
             "data" => block_type.defaults.is_a?(Hash) ? block_type.defaults.deep_dup : {}}
    render partial: "content_form/block", locals: {
      block: block, scope: helpers.content_scope(scope)[helpers.content_row_key],
      depth: params[:depth].to_i, errors: [], open: true
    }
  end

  private

  # Adding a block is part of writing a page, entry or global, whichever
  # this form is.
  def require_content_write
    head :forbidden unless WRITE_CAPABILITIES.any? { Current.user&.can?(it) }
  end
end
