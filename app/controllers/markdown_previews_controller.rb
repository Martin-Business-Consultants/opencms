# frozen_string_literal: true

# A Markdown field's Preview tab: the text as it will render, drawn on the
# server (Markdown.to_html) into the field's preview frame.
class MarkdownPreviewsController < ApplicationController
  requires_capability "pages:read", only: :create

  def create
    render partial: "markdown_previews/preview", locals: {text: params[:text].to_s}
  end
end
