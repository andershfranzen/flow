class EncryptWebhookSecrets < ActiveRecord::Migration[8.1]
  def up
    Webhook.find_each do |webhook|
      next if webhook.encrypted_attribute?(:secret)

      # Reading uses the model's legacy plaintext fallback; update_columns
      # serializes the value through Active Record Encryption before writing.
      webhook.update_columns(secret: webhook.secret)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
