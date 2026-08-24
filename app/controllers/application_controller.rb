class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  private

  # Session cookie (SPA) or Bearer token (API/MCP). Session carries the agent's
  # session_token so a password change invalidates it (C5).
  def current_agent
    return @current_agent if defined?(@current_agent)
    @current_agent =
      if (token = bearer_token)
        @current_api_token = ApiToken.authenticate(token)
        @current_api_token&.agent
      elsif session[:agent_id]
        agent = Agent.find_by(id: session[:agent_id])
        agent if agent && ActiveSupport::SecurityUtils.secure_compare(agent.session_token, session[:session_token].to_s)
      end
  end

  def current_api_token
    current_agent
    @current_api_token
  end

  def bearer_token
    request.headers["Authorization"]&.match(/\ABearer (.+)\z/)&.[](1)
  end

  def require_agent!
    head :unauthorized unless current_agent
  end

  def require_admin!
    require_agent!
    head :forbidden if current_agent && !current_agent.admin?
  end

  # Read-scope tokens may only perform reads (G2).
  def require_write_scope!
    return if request.get? || request.head?
    head :forbidden if current_api_token && !current_api_token.write?
  end

  # Token requests are not CSRF-able; only enforce CSRF for cookie sessions.
  def verified_request?
    bearer_token.present? || super
  end
end
