# frozen_string_literal: true

# Settings → AI held two unrelated things: connection credentials for the
# built-in assistant (provider / default_model / api_key), and a brand brief
# (voice, audience, key facts, style notes) that was prepended to every
# prompt.
#
# The assistant is gone, but the brief is not about AI — it is how the
# workspace wants its content written, and it is now published through
# /api/manifest so an external agent (Claude, Codex, …) writes in the same
# voice. It moves to its own `brand` settings key; the credentials are
# dropped, since a key nothing can use is only a liability.
#
# Runs per tenant database, like every other migration here — `settings` is
# a tenanted table.
class MoveAiBrandContextToBrandSetting < ActiveRecord::Migration[8.0]
  BRAND_FIELDS = %w[brand_voice audience key_facts style_notes].freeze

  def up
    ai = select_one_setting("ai")
    return unless ai

    data  = parse_json(ai["data"])
    brief = data.slice(*BRAND_FIELDS).reject { |_, v| v.to_s.strip.empty? }

    if brief.any?
      brand = select_one_setting("brand")
      merged = brief.merge(parse_json(brand&.fetch("data", nil))) # existing brand values win

      if brand
        execute_setting_update("brand", merged)
      else
        execute_setting_insert("brand", merged)
      end
    end

    execute("DELETE FROM settings WHERE key = 'ai'")
  end

  # Puts the brief back under `ai`. The provider credentials were deleted,
  # not archived, so they do not come back.
  def down
    brand = select_one_setting("brand")
    return unless brand

    brief = parse_json(brand["data"]).slice(*BRAND_FIELDS)
    return if brief.empty?

    if select_one_setting("ai")
      execute_setting_update("ai", brief)
    else
      execute_setting_insert("ai", brief)
    end
  end

  private

  def select_one_setting(key)
    select_one("SELECT data FROM settings WHERE key = #{q(key)}")
  end

  def execute_setting_insert(key, data)
    now = Time.current.utc.iso8601(6)
    execute(<<~SQL)
      INSERT INTO settings (key, data, created_at, updated_at)
      VALUES (#{q(key)}, #{q(data.to_json)}, #{q(now)}, #{q(now)})
    SQL
  end

  def execute_setting_update(key, data)
    execute(<<~SQL)
      UPDATE settings
      SET data = #{q(data.to_json)}, updated_at = #{q(Time.current.utc.iso8601(6))}
      WHERE key = #{q(key)}
    SQL
  end

  # Quote through the migration's own connection. `ActiveRecord::Base` is
  # untenanted here and raises NoTenantError the moment it's asked for one.
  def q(value)
    connection.quote(value)
  end

  # The column is `json`, but SQLite hands it back as a string.
  def parse_json(raw)
    return {} if raw.blank?
    return raw if raw.is_a?(Hash)

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end
end
