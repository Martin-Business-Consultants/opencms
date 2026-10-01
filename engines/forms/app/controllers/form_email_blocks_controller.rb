# frozen_string_literal: true

# GET /form_email_blocks/new?type=email_text&scope=form_email[blocks]&depth=1 —
# one new block row for a form email's "Add block" picker, as
# content_blocks#new is for a page's, but of FormEmail::BlockTypes.
class FormEmailBlocksController < ApplicationController
  include PluginGated
  plugin :forms

  requires_capability "forms:write", only: :new

  def new
    block = FormEmail::BlockTypes.build(params[:type]) or return head(:not_found)
    scope = params[:scope].to_s
    return head(:bad_request) unless scope.match?(ContentBlocksController::SCOPE)

    render :new, layout: false, locals: {block: block, scope: scope, depth: params[:depth].to_i}
  end
end
