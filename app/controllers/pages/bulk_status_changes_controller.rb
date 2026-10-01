# frozen_string_literal: true

# Content › Pages: one status for every ticked page. One save per page (not
# update_all) so the status webhooks and the debounced deploy fire, as they do
# for a single edit.
class Pages::BulkStatusChangesController < ApplicationController
  requires_capability "pages:publish", only: :create

  def create
    status = params[:status].to_s
    paths = Array(params[:slugs]).map(&:to_s).reject(&:empty?)

    if Page::STATUSES.exclude?(status)
      redirect_to pages_path, alert: "Pick a status to set."
    else
      pages = Page.change_status_of(Page.where(path: paths).to_a, to: status)
      redirect_to pages_path, notice: "#{pages.size} #{"page".pluralize(pages.size)} set to #{status}"
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to pages_path, alert: "#{e.record.path}: #{e.record.errors.full_messages.to_sentence}"
  end
end
