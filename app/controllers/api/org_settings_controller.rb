class Api::OrgSettingsController < Api::BaseController
  before_action :require_admin!, only: [ :update ]

  def show
    render json: settings_json
  end

  def update
    permitted = params.permit(:site_name, :base_url, :notify_from,
                              :ms_client_id, :ms_client_secret, :ms_tenant,
                              :google_client_id, :google_client_secret)
    permitted.delete(:ms_client_secret) if permitted[:ms_client_secret].blank?
    permitted.delete(:google_client_secret) if permitted[:google_client_secret].blank?
    OrgSetting.current.update!(permitted)
    render json: settings_json
  end

  private

  def settings_json
    s = OrgSetting.current
    s.as_json(only: [ :site_name, :base_url, :notify_from, :ms_client_id, :ms_tenant, :google_client_id ])
     .merge("ms_client_secret_set" => s.ms_client_secret.present?,
            "google_client_secret_set" => s.google_client_secret.present?,
            "microsoft_configured" => MailOauth.configured?("microsoft"),
            "google_configured" => MailOauth.configured?("google"))
  end
end
