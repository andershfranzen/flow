require "net/http"

# Microsoft Dynamics 365 (Dataverse) lookups for the Insights sidebar.
# Server-to-server: client-credentials against the same Entra app as mailbox
# OAuth/SSO, so the only extra setup is an application user in Dynamics with
# read rights on contacts/accounts, plus the org URL in Settings.
class Crm
  class Error < StandardError; end

  GENERIC_DOMAINS = %w[gmail.com googlemail.com outlook.com hotmail.com yahoo.com
                       icloud.com live.com msn.com proton.me protonmail.com].freeze

  def self.settings = OrgSetting.current

  def self.configured?
    settings.crm_enabled && settings.crm_url.present? &&
      settings.ms_client_id.present? && settings.ms_client_secret.present? &&
      settings.ms_tenant.present? && settings.ms_tenant != "common"
  end

  def self.base_url = settings.crm_url.to_s.chomp("/")

  # Contact by exact email, with its parent account expanded; if no contact,
  # try matching an account by the email's company domain. Cached briefly.
  def self.lookup(email)
    return nil unless configured?
    email = email.to_s.downcase.strip
    return nil unless email.match?(/\A[^\s@]+@[^\s@]+\z/)
    Rails.cache.fetch("crm-lookup-#{email}", expires_in: 10.minutes) do
      contact = find_contact(email)
      account = contact&.delete("parentcustomerid_account") ||
                find_account_by_domain(email.split("@").last)
      { "contact" => contact, "account" => account }
    end
  end

  def self.find_contact(email)
    get("contacts",
        "$select" => "contactid,fullname,jobtitle,emailaddress1,telephone1,mobilephone,address1_city,address1_country",
        "$expand" => "parentcustomerid_account($select=accountid,name,websiteurl,telephone1,address1_city,address1_country)",
        "$filter" => "emailaddress1 eq '#{odata_quote(email)}'",
        "$top" => 1)["value"]&.first
  end

  def self.find_account_by_domain(domain)
    return nil if GENERIC_DOMAINS.include?(domain)
    get("accounts",
        "$select" => "accountid,name,websiteurl,telephone1,emailaddress1,address1_city,address1_country",
        "$filter" => "contains(websiteurl,'#{odata_quote(domain)}') or contains(emailaddress1,'#{odata_quote("@" + domain)}')",
        "$top" => 1)["value"]&.first
  end

  def self.record_url(entity, id)
    "#{base_url}/main.aspx?pagetype=entityrecord&etn=#{entity}&id=#{id}"
  end

  def self.get(entity, params)
    uri = URI("#{base_url}/api/data/v9.2/#{entity}")
    uri.query = URI.encode_www_form(params)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.get("#{uri.path}?#{uri.query}",
               "Authorization" => "Bearer #{access_token}", "Accept" => "application/json",
               "OData-MaxVersion" => "4.0", "OData-Version" => "4.0")
    end
    raise Error, "Dynamics returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.access_token
    Rails.cache.fetch("crm-token-#{settings.ms_tenant}-#{base_url}", expires_in: 50.minutes) do
      MailOauth.post_token(
        { token_url: "https://login.microsoftonline.com/#{settings.ms_tenant}/oauth2/v2.0/token",
          client_id: settings.ms_client_id, client_secret: settings.ms_client_secret },
        grant_type: "client_credentials", scope: "#{base_url}/.default"
      ).fetch("access_token")
    end
  rescue MailOauth::Error => e
    raise Error, e.message
  end

  # OData string literals escape single quotes by doubling them.
  def self.odata_quote(value) = value.gsub("'", "''")
end
