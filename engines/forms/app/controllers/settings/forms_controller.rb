# frozen_string_literal: true

# Settings › Forms: who form emails come from, and the spam check a public
# submission has to pass (TurnstileVerifier). Stored in the `forms_settings`
# setting, which the mailers and the submission endpoint read; the captcha
# secret keys in its encrypted `secrets`, never shown again once saved.
class Settings::FormsController < Settings::BaseController
  include PluginGated
  plugin :forms

  requires_capability "forms:read",  only: :show
  requires_capability "forms:write", only: :update

  SETTING_KEY = Forms::SETTING_KEY
  FIELDS = %w[from_name from_email captcha_provider turnstile_site_key recaptcha_site_key].freeze
  SECRET_FIELDS = %w[turnstile_secret_key recaptcha_secret_key].freeze
  CAPTCHA_PROVIDERS = {"none" => "None", "turnstile" => "Cloudflare Turnstile", "recaptcha" => "Google reCAPTCHA"}.freeze

  def show
    data = Setting.get(SETTING_KEY)
    @settings = FIELDS.index_with { |field| data[field].to_s }
    @settings["captcha_provider"] = "none" if @settings["captcha_provider"].blank?
    @secrets_set = SECRET_FIELDS.index_with { |field| Forms.captcha_secret(field).present? }
  end

  # A blank secret field keeps what's saved (the page never shows it); a new
  # one is stored encrypted and the plain copy an older install kept in the
  # data is dropped.
  def update
    attrs = params.require(:settings).permit(*FIELDS, *SECRET_FIELDS).to_h
    secrets = attrs.extract!(*SECRET_FIELDS).select { |_, value| value.to_s.strip.present? }

    Setting.set(SETTING_KEY, attrs)
    if secrets.any?
      Setting.set_secret(SETTING_KEY, secrets)
      Setting.unset(SETTING_KEY, *secrets.keys)
    end
    Event.record("settings.forms_updated", fields: attrs.keys + secrets.keys)
    redirect_to settings_forms_path, notice: "Form settings saved"
  end
end
