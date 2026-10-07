encryption = Rails.application.config.active_record.encryption
creds = Rails.app.creds

encryption.primary_key = creds.option(:active_record_encryption, :primary_key)
encryption.deterministic_key = creds.option(:active_record_encryption, :deterministic_key)
encryption.key_derivation_salt = creds.option(:active_record_encryption, :key_derivation_salt)

if encryption.primary_key.blank? && !Rails.env.production?
  encryption.primary_key = "dev-primary-key-not-for-production-0000"
  encryption.deterministic_key = "dev-deterministic-key-not-for-production"
  encryption.key_derivation_salt = "dev-key-derivation-salt-not-for-production"
end
