# frozen_string_literal: true

# The captcha secret keys on Settings › Forms used to sit in the plain `data`
# of the `forms_settings` setting. Move them into its encrypted `secrets`,
# where the other integration credentials live. Readers fall back to a plain
# value, so an install that hasn't run this yet keeps working.
class EncryptFormCaptchaSecrets < ActiveRecord::Migration[8.1]
  NAMES = %w[turnstile_secret_key recaptcha_secret_key].freeze

  def up
    record = Setting.find_by(key: "forms_settings") or return
    plain = (record.data || {}).slice(*NAMES).select { |_, value| value.to_s.strip.present? }
    return if plain.empty?

    Setting.set_secret("forms_settings", plain)
    Setting.unset("forms_settings", *plain.keys)
  end

  def down
    record = Setting.find_by(key: "forms_settings") or return
    secrets = record.secrets_hash.slice(*NAMES)
    return if secrets.empty?

    Setting.set("forms_settings", secrets)
  end
end
