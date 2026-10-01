# frozen_string_literal: true

# Keys for ActiveRecord encryption. The only encrypted attribute today is
# `ApiToken#token`, which has to be *decryptable* — the whole point is that
# a user can come back later and read their own token.
#
# Resolution order, per key:
#
#   1. ENV — AR_ENCRYPTION_PRIMARY_KEY / _DETERMINISTIC_KEY / _KEY_DERIVATION_SALT
#   2. derived from secret_key_base
#
# (2) is what keeps dev, test, and already-deployed instances working with
# no extra setup. The trade-off: token decryptability is tied to
# secret_key_base, so rotating that leaves stored tokens unreadable (the UI
# degrades to "rotate to reveal" — nothing is lost but the old plaintext).
# Set (1) to decouple the two.
#
# This runs as a plain initializer rather than `config.active_record.encryption.*`
# because ActiveRecord's own encryption initializer has already fired by the
# time config/initializers/* load; calling `configure` directly is what that
# initializer does anyway.
module ActiveRecordEncryptionKeys
  KEYS = {
    primary_key:         "AR_ENCRYPTION_PRIMARY_KEY",
    deterministic_key:   "AR_ENCRYPTION_DETERMINISTIC_KEY",
    key_derivation_salt: "AR_ENCRYPTION_KEY_DERIVATION_SALT"
  }.freeze

  def self.resolve
    KEYS.to_h { |name, env_name| [name, fetch(name, env_name)] }
  end

  def self.fetch(name, env_name)
    ENV[env_name].presence || derive(name)
  end

  def self.derive(name)
    Rails.application.key_generator.generate_key("active_record_encryption/#{name}", 32).unpack1("H*")
  end
end

ActiveRecord::Encryption.configure(**ActiveRecordEncryptionKeys.resolve)
