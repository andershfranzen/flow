class Api::SessionsController < Api::BaseController
  skip_before_action :require_agent!, only: [ :create, :show ]
  skip_before_action :require_write_scope!
  # Brute-force delay (C5/I4).
  rate_limit to: 10, within: 3.minutes, only: :create

  # GET /api/session — who am I + CSRF token for the SPA (C4/H19)
  def show
    if current_agent
      render json: agent_json(current_agent).merge(csrf_token: form_authenticity_token)
    else
      render json: { agent: nil, csrf_token: form_authenticity_token,
                     sso: { enabled: Sso.enabled?, password_login: Sso.password_login_allowed? },
                     org: { site_name: OrgSetting.current.site_name,
                            logo_url: OrgSetting.current.logo_url,
                            theme: OrgSetting.current.theme || {} } }
    end
  end

  def create
    unless Sso.password_login_allowed?
      return render json: { error: "password_login_disabled",
                            details: [ "This Flow uses Microsoft sign-in" ] }, status: :forbidden
    end
    agent = Agent.find_by(email: params[:email].to_s.downcase.strip)
    if agent&.authenticate(params[:password].to_s)
      if agent.otp_required?
        unless params[:otp_code].present? && Totp.valid?(agent.otp_secret, params[:otp_code])
          return render json: { error: "otp_required" }, status: :unauthorized
        end
      end
      reset_session
      session[:agent_id] = agent.id
      session[:session_token] = agent.session_token
      session[:seen_at] = Time.current.to_i
      agent.update_column(:last_seen_at, Time.current)
      render json: agent_json(agent).merge(csrf_token: form_authenticity_token)
    else
      render json: { error: "invalid_credentials" }, status: :unauthorized
    end
  end

  def destroy
    reset_session
    head :no_content
  end

  private

  def agent_json(agent)
    { agent: agent.as_json(only: [ :id, :email, :name, :role, :locale, :timezone ])
                  .merge(notify_prefs: agent.notify_prefs, ui_prefs: agent.ui_prefs || {}),
      org: { default_signature: OrgSetting.current.default_signature,
             site_name: OrgSetting.current.site_name,
             logo_url: OrgSetting.current.logo_url,
             theme: OrgSetting.current.theme || {},
             crm_enabled: Crm.configured? } }
  end
end
