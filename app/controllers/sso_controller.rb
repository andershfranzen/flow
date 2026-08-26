# Browser-facing Microsoft sign-in: /auth/microsoft/start redirects to Entra,
# the callback establishes the same session password login would.
class SsoController < ActionController::Base
  rate_limit to: 10, within: 1.minute, name: "sso", only: [ :start, :callback ]

  def start
    return redirect_to "/login" unless OrgSetting.current.ms_sso_enabled
    return fail_login unless Sso.enabled?
    session[:sso_state_nonce] = SecureRandom.hex(16)
    redirect_to Sso.authorize_url(redirect_uri, browser_nonce: session[:sso_state_nonce]), allow_other_host: true
  rescue Sso::Error
    fail_login
  end

  def callback
    return redirect_to "/login" unless OrgSetting.current.ms_sso_enabled
    return fail_login unless Sso.enabled?
    if params[:error].present?
      session.delete(:sso_state_nonce)
      return fail_login
    end
    agent = Sso.authenticate!(code: params.require(:code), state: params.require(:state),
                              redirect_uri: redirect_uri, browser_nonce: session.delete(:sso_state_nonce))
    reset_session
    session[:agent_id] = agent.id
    session[:session_token] = agent.session_token
    session[:seen_at] = Time.current.to_i
    agent.update_column(:last_seen_at, Time.current)
    redirect_to "/inbox"
  rescue Sso::Error, ActionController::ParameterMissing
    fail_login
  end

  private

  def fail_login
    base = OrgSetting.current.canonical_base_url
    return render plain: "sign_in_failed", status: :unprocessable_entity unless base

    redirect_to "#{base}/login?sso_error=sign_in_failed", allow_other_host: true
  end

  def redirect_uri
    base = OrgSetting.current.canonical_base_url
    raise Sso::Error, "SSO redirect URI is not configured" unless base
    "#{base}/auth/microsoft/callback"
  end
end
