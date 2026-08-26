# Dynamics 365 lookup for the Insights sidebar.
class Api::CrmController < Api::BaseController
  def lookup
    return render json: { configured: false } unless Crm.configured?
    email = params.require(:email).to_s.downcase.strip
    return render json: { configured: true, contact: nil, account: nil } unless Customer.accessible_for_email(email, current_agent)

    data = Crm.lookup(email) || {}
    contact = data["contact"]
    account = data["account"]
    render json: {
      configured: true,
      contact: contact && {
        name: contact["fullname"], title: contact["jobtitle"], email: contact["emailaddress1"],
        phone: contact["telephone1"], mobile: contact["mobilephone"],
        city: contact["address1_city"], country: contact["address1_country"],
        url: Crm.record_url("contact", contact["contactid"])
      },
      account: account && {
        name: account["name"], website: safe_website_url(account["websiteurl"]), phone: account["telephone1"],
        city: account["address1_city"], country: account["address1_country"],
        url: Crm.record_url("account", account["accountid"])
      }
    }
  rescue Crm::Error => e
    render json: { configured: true, error: e.message }, status: :bad_gateway
  end

  private

  def safe_website_url(value)
    uri = URI.parse(value.to_s.strip)
    return unless uri.host.present? && %w[http https].include?(uri.scheme.to_s.downcase)
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end
