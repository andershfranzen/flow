class Api::OrgSettingsController < Api::BaseController
  before_action :require_admin!, only: [ :update ]

  def show
    render json: settings_json
  end

  def update
    permitted = params.permit(:site_name, :base_url, :notify_from, :default_signature,
                              :ms_client_id, :ms_client_secret, :ms_tenant,
                              :ms_sso_enabled, :sso_auto_provision, :sso_allowed_domains, :mcp_enabled, :crm_enabled, :crm_url,
                              :google_client_id, :google_client_secret)
    permitted.delete(:ms_client_secret) if permitted[:ms_client_secret].blank?
    permitted.delete(:google_client_secret) if permitted[:google_client_secret].blank?
    settings = OrgSetting.current
    settings.update!(permitted)
    if params[:theme].present?
      settings.update!(theme: params[:theme].to_unsafe_h
        .slice(*OrgSetting::THEME_KEYS)
        .select { |_k, v| v.to_s.match?(/\A#\h{6}\z/) })
    end
    if params[:logo].respond_to?(:content_type)
      unless params[:logo].content_type.match?(%r{\Aimage/(png|jpeg|webp)\z}) && params[:logo].size <= 1.megabyte
        return render json: { error: "invalid_logo", details: [ "PNG, JPEG or WebP up to 1 MB" ] },
                      status: :unprocessable_entity
      end
      settings.logo.attach(params[:logo])
    end
    settings.logo.purge if params[:remove_logo].present?
    render json: settings_json
  end

  private

  def settings_json
    s = OrgSetting.current
    s.as_json(only: [ :site_name, :base_url, :notify_from, :default_signature, :ms_client_id, :ms_tenant, :google_client_id,
                      :ms_sso_enabled, :sso_auto_provision, :sso_allowed_domains, :mcp_enabled, :crm_enabled, :crm_url ])
     .merge("logo_url" => s.logo_url,
            "theme" => s.theme || {},
            "ms_client_secret_set" => s.ms_client_secret.present?,
            "google_client_secret_set" => s.google_client_secret.present?,
            "microsoft_configured" => MailOauth.configured?("microsoft"),
            "google_configured" => MailOauth.configured?("google"))
  end
end
