# frozen_string_literal: true

module Hello
  # A plugin model: its own prefixed table, pointing at core records by id.
  class Greeting < ApplicationRecord
    KEEP = 100

    belongs_to :user, optional: true

    validates :message, presence: true, length: {maximum: 200}

    scope :newest_first, -> { order(created_at: :desc, id: :desc) }

    def self.default_message = Setting.get("hello")["default_message"].presence || "Hello!"

    # The nightly task: keep the newest KEEP.
    def self.tidy
      where.not(id: newest_first.limit(KEEP).select(:id)).delete_all
    end

    # page.published.cms, counted in the plugin's setting.
    def self.record_publication
      Setting.set("hello", {"pages_published" => Setting.get("hello")["pages_published"].to_i + 1})
    end
  end
end
