# OAuth connect flow for Microsoft 365 / Google mailboxes (A5).
class Api::OauthController < Api::BaseController
  before_action :require_admin!

  # POST /api/oauth/:provider/start { mailbox_id } → { url } for a popup
  def start
    provider = params[:provider]
    return render json: { error: "unknown_provider" }, status: :unprocessable_entity unless MailOauth::PROVIDERS.include?(provider)
    unless MailOauth.configured?(provider)
      return render json: { error: "provider_not_configured",
                            details: [ "Add the #{provider} client id and secret under Settings → Organisation first" ] },
                    status: :unprocessable_entity
    end
    return render json: { error: "oauth_not_configured" }, status: :unprocessable_entity unless redirect_uri

    mailbox = Mailbox.find(params.require(:mailbox_id))
    render json: { url: MailOauth.authorize_url(provider, mailbox, redirect_uri) }
  end

  private

  def redirect_uri
    base = OrgSetting.current.canonical_base_url
    "#{base}/oauth/callback" if base
  end
end
