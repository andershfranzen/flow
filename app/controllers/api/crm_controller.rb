# Dynamics 365 lookup for the Insights sidebar.
class Api::CrmController < Api::BaseController
  def lookup
    return render json: { configured: false } unless Crm.configured?
    data = Crm.lookup(params.require(:email)) || {}
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
        name: account["name"], website: account["websiteurl"], phone: account["telephone1"],
        city: account["address1_city"], country: account["address1_country"],
        url: Crm.record_url("account", account["accountid"])
      }
    }
  rescue Crm::Error => e
    render json: { configured: true, error: e.message }, status: :bad_gateway
  end
end
