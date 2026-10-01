# frozen_string_literal: true

require "forms/engine"

# Forms: the forms a site renders (Form, its fields and two emails), the
# public endpoint they post to, and the Submissions inbox. Bundled and on by
# default.
#
# Its models keep the names and tables they had in the core (forms,
# form_submissions, form_emails) — they predate plugins; a new table would be
# prefixed.
module Forms
  # Sender and spam-protection settings (Settings › Forms).
  SETTING_KEY = "forms_settings"

  # A captcha secret key: from the setting's encrypted `secrets`, or the plain
  # value an install saved before they were encrypted (the
  # EncryptFormCaptchaSecrets migration moves those).
  def self.captcha_secret(name)
    Setting.secret(SETTING_KEY, name) || Setting.get(SETTING_KEY)[name.to_s].to_s.strip.presence
  end
end
