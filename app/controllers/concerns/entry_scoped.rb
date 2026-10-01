# frozen_string_literal: true

# Loads the entry named in the URL (`…/entries/:entry_slug/…`) within its
# collection (CollectionScoped).
module EntryScoped
  extend ActiveSupport::Concern

  included do
    include CollectionScoped
    before_action :set_entry
  end

  private

  def set_entry
    @entry = @collection.entries.find_by!(slug: params[:entry_slug])
  end
end
