# frozen_string_literal: true

# Loads the global named in the URL (`/globals/:global_slug/…`).
module GlobalScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_global
  end

  private

  def set_global
    @global = Global.find_by!(slug: params[:global_slug])
  end
end
