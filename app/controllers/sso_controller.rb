# Browser-facing Microsoft sign-in: /auth/microsoft/start redirects to Entra,
# the callback establishes the same session password login would.
class SsoController < ActionController::Base
  def start
    return redirect_to "/login" unless Sso.enabled?
    redirect_to Sso.authorize_url(redirect_uri), allow_other_host: true
  end

  def callback
    return redirect_to "/login" unless Sso.enabled?
    if params[:error].present?
      return fail_login(params[:error_description].presence || params[:error])
    end
    agent = Sso.authenticate!(code: params.require(:code), state: params.require(:state),
                              redirect_uri: redirect_uri)
    reset_session
    session[:agent_id] = agent.id
    session[:session_token] = agent.session_token
    session[:seen_at] = Time.current.to_i
    agent.update_column(:last_seen_at, Time.current)
    redirect_to "/inbox"
  rescue Sso::Error, ActionController::ParameterMissing => e
    fail_login(e.message)
  end

  private

  def fail_login(message)
    redirect_to "/login?#{{ sso_error: message.to_s.truncate(200) }.to_query}"
  end

  def redirect_uri
    base = OrgSetting.current.base_url.presence || request.base_url
    "#{base.chomp('/')}/auth/microsoft/callback"
  end
end
