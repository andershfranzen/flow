require "net/smtp"

# AUTH XOAUTH2 for Net::SMTP (Microsoft 365 / Gmail). Registered by class
# definition; `mail`'s :smtp delivery reaches it via authentication: :xoauth2
# with the access token passed as the password.
class SmtpXoauth2Authenticator < Net::SMTP::Authenticator
  auth_type :xoauth2

  def auth(user, secret)
    sasl = "user=#{user}\1auth=Bearer #{secret}\1\1"
    finish("AUTH XOAUTH2 #{Base64.strict_encode64(sasl)}")
  end
end
