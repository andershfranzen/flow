require "test_helper"

class MailOauthTest < ActiveSupport::TestCase
  def stub_tokens(response)
    MailOauth.singleton_class.alias_method :orig_post_token, :post_token
    MailOauth.define_singleton_method(:post_token) { |*args| response.respond_to?(:call) ? response.call(*args) : response }
    yield
  ensure
    MailOauth.singleton_class.alias_method :post_token, :orig_post_token
    MailOauth.singleton_class.remove_method :orig_post_token
  end

  def stub_smtp(smtp)
    Net::SMTP.singleton_class.alias_method :orig_new, :new
    Net::SMTP.define_singleton_method(:new) { |*| smtp }
    yield
  ensure
    Net::SMTP.singleton_class.alias_method :new, :orig_new
    Net::SMTP.singleton_class.remove_method :orig_new
  end

  setup do
    OrgSetting.current.update!(ms_client_id: "msid", ms_client_secret: "mssecret", ms_tenant: "contoso",
                               google_client_id: "gid", google_client_secret: "gsecret")
    @mailbox = Mailbox.create!(address: "support@contoso.com", name: "Support")
  end

  test "configured? reflects org settings" do
    assert MailOauth.configured?("microsoft")
    assert MailOauth.configured?("microsoft_app")
    assert MailOauth.configured?("google")
    OrgSetting.current.update!(ms_tenant: "common")
    refute MailOauth.configured?("microsoft_app")
    assert MailOauth.configured?("microsoft")
    OrgSetting.current.update!(ms_client_secret: nil)
    refute MailOauth.configured?("microsoft")
  end

  test "authorize_url carries tenant, scopes, and verifiable state" do
    url = MailOauth.authorize_url("microsoft", @mailbox, "https://flow.example.com/oauth/callback")
    assert_includes url, "login.microsoftonline.com/contoso/oauth2/v2.0/authorize"
    assert_includes url, "IMAP.AccessAsUser.All"
    state = Rack::Utils.parse_query(URI(url).query)["state"]
    assert_equal({ mailbox_id: @mailbox.id, provider: "microsoft" }, MailOauth.verify_state!(state).symbolize_keys)
  end

  test "connect! stores tokens and fills provider server defaults" do
    tokens = { "access_token" => "at1", "refresh_token" => "rt1", "expires_in" => 3600 }
    stub_tokens(tokens) do
      MailOauth.connect!(@mailbox, "microsoft", "the-code", "https://x/oauth/callback")
    end
    @mailbox.reload
    assert_equal "microsoft", @mailbox.auth_kind
    assert @mailbox.oauth_connected?
    assert_equal "outlook.office365.com", @mailbox.imap_host
    assert_equal "smtp.office365.com", @mailbox.smtp_host
    assert_equal "support@contoso.com", @mailbox.imap_user
    assert @mailbox.imap_configured?
    assert @mailbox.smtp_configured?
  end

  test "access_token! uses cache until near expiry, then refreshes" do
    @mailbox.update!(auth_kind: "google", oauth_refresh_token: "rt", oauth_access_token: "cached",
                     oauth_expires_at: 30.minutes.from_now)
    assert_equal "cached", MailOauth.access_token!(@mailbox)

    @mailbox.update!(oauth_expires_at: 10.seconds.from_now)
    stub_tokens({ "access_token" => "fresh", "expires_in" => 3599 }) do
      assert_equal "fresh", MailOauth.access_token!(@mailbox)
    end
    assert_equal "rt", @mailbox.reload.oauth_refresh_token, "refresh token kept when not rotated"
  end

  test "app-only Microsoft mailboxes use client credentials without a user token" do
    @mailbox.update!(auth_kind: "microsoft_app")
    request = nil
    stub_tokens(->(_config, params) { request = params; { "access_token" => "app-token" } }) do
      assert_equal "app-token", MailOauth.access_token!(@mailbox)
    end

    assert_equal "client_credentials", request[:grant_type]
    assert_equal "https://outlook.office365.com/.default", request[:scope]
    assert @mailbox.oauth_connected?
    assert_equal "outlook.office365.com", @mailbox.imap_host
    assert_equal "smtp.office365.com", @mailbox.smtp_host
    assert_equal @mailbox.address, @mailbox.imap_user
    assert_equal @mailbox.address, @mailbox.smtp_user
    assert_nil @mailbox.oauth_refresh_token
  end

  test "smtp_options switches to xoauth2 for oauth mailboxes" do
    @mailbox.update!(auth_kind: "microsoft", oauth_refresh_token: "rt", oauth_access_token: "tok",
                     oauth_expires_at: 1.hour.from_now, smtp_host: "smtp.office365.com")
    opts = @mailbox.smtp_options
    assert_equal :xoauth2, opts[:authentication]
    assert_equal "tok", opts[:password]
    assert_equal "support@contoso.com", opts[:user_name]
  end

  test "connection test uses the configured SMTP authenticator" do
    @mailbox.update!(auth_kind: "microsoft", oauth_refresh_token: "rt", oauth_access_token: "tok",
                     oauth_expires_at: 1.hour.from_now, smtp_host: "smtp.office365.com")
    authentication = nil
    smtp = Object.new
    smtp.define_singleton_method(:enable_starttls_auto) {}
    smtp.define_singleton_method(:open_timeout=) { |_| }
    smtp.define_singleton_method(:start) { |_domain, _user, _secret, auth, &block| authentication = auth; block.call }

    stub_smtp(smtp) { assert @mailbox.test_smtp[:ok] }
    assert_equal :xoauth2, authentication
  end

  test "xoauth2 smtp authenticator is registered" do
    assert_equal SmtpXoauth2Authenticator, Net::SMTP::Authenticator.auth_class(:xoauth2)
  end

  test "tokens are encrypted at rest" do
    @mailbox.update!(oauth_refresh_token: "super-secret-rt")
    raw = Mailbox.connection.select_value("SELECT oauth_refresh_token FROM mailboxes WHERE id = #{@mailbox.id}")
    refute_includes raw.to_s, "super-secret-rt"
  end
end
