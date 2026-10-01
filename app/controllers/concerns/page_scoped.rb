# frozen_string_literal: true

# For controllers nested under a page (/pages/:page_slug/…): loads it by its
# full path, which may contain slashes.
module PageScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_page
  end

  private

  def set_page
    @page = Page.find_by!(path: params[:page_slug])
  end
end
