# Mailbox IMAP/SMTP passwords encrypted at rest (A1). Keys derive from
# secret_key_base so the only secret an operator manages is SECRET_KEY_BASE (J2).
Rails.application.configure do
  generator = ActiveSupport::KeyGenerator.new(
    Rails.application.secret_key_base, hash_digest_class: OpenSSL::Digest::SHA256
  )
  config.active_record.encryption.primary_key = generator.generate_key("ar_encryption_primary", 32).unpack1("H*")
  config.active_record.encryption.deterministic_key = generator.generate_key("ar_encryption_deterministic", 32).unpack1("H*")
  config.active_record.encryption.key_derivation_salt = generator.generate_key("ar_encryption_salt", 32).unpack1("H*")
end
