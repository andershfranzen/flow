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
      render json: { agent: nil, csrf_token: form_authenticity_token }
    end
  end

  def create
    agent = Agent.find_by(email: params[:email].to_s.downcase.strip)
    if agent&.authenticate(params[:password].to_s)
      reset_session
      session[:agent_id] = agent.id
      session[:session_token] = agent.session_token
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
                  .merge(notify_prefs: agent.notify_prefs) }
  end
end
