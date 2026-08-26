require "test_helper"
require_relative "../../db/migrate/20260826000000_encrypt_webhook_secrets"

class WebhooksTest < ActionDispatch::IntegrationTest
  setup do
    @admin = Agent.create!(email: "admin@example.com", name: "Admin", password: "secret123", role: "admin")
    post "/api/session", params: { email: "admin@example.com", password: "secret123" }
  end

  test "returns a signing secret only when creating a webhook" do
    post "/api/webhooks", params: { url: "https://hooks.example.com/flow", enabled: true,
                                     events: [ "message.inbound" ] }
    assert_response :created
    created = response.parsed_body
    secret = created["secret"]
    assert secret.present?

    webhook = Webhook.find(created["id"])
    raw_secret = Webhook.connection.select_value(
      Webhook.sanitize_sql_array([ "SELECT secret FROM webhooks WHERE id = ?", webhook.id ])
    )
    refute_equal secret, raw_secret, "new webhook secrets must be encrypted at rest"
    assert_equal secret, webhook.secret

    get "/api/webhooks"
    assert_response :success
    listed = response.parsed_body.find { |entry| entry["id"] == webhook.id }
    refute listed.key?("secret")

    patch "/api/webhooks/#{webhook.id}", params: { enabled: false }
    assert_response :success
    refute response.parsed_body.key?("secret")
  end

  test "legacy plaintext secrets remain readable for delivery" do
    webhook = Webhook.create!(url: "https://hooks.example.com/legacy", secret: "legacy-secret")
    Webhook.connection.execute(
      "UPDATE webhooks SET secret = #{Webhook.connection.quote("legacy-secret")} WHERE id = #{webhook.id}"
    )

    assert_equal "legacy-secret", Webhook.find(webhook.id).secret
  end

  test "migration encrypts legacy plaintext secrets without changing their value" do
    already_encrypted = Webhook.create!(url: "https://hooks.example.com/already", secret: "already-secret")
    ciphertext = Webhook.connection.select_value(
      Webhook.sanitize_sql_array([ "SELECT secret FROM webhooks WHERE id = ?", already_encrypted.id ])
    )
    webhook = Webhook.create!(url: "https://hooks.example.com/migrate", secret: "legacy-secret")
    Webhook.connection.execute(
      "UPDATE webhooks SET secret = #{Webhook.connection.quote("legacy-secret")} WHERE id = #{webhook.id}"
    )

    EncryptWebhookSecrets.new.up

    raw_secret = Webhook.connection.select_value(
      Webhook.sanitize_sql_array([ "SELECT secret FROM webhooks WHERE id = ?", webhook.id ])
    )
    refute_equal "legacy-secret", raw_secret
    assert_equal "legacy-secret", webhook.reload.secret
    assert_equal ciphertext, Webhook.connection.select_value(
      Webhook.sanitize_sql_array([ "SELECT secret FROM webhooks WHERE id = ?", already_encrypted.id ])
    )
  end
end
