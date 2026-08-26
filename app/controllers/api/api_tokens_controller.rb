class Api::ApiTokensController < Api::BaseController
  before_action :require_cookie_session_for_create, only: :create

  def index
    render json: current_agent.api_tokens.order(:id)
                 .as_json(only: [ :id, :name, :scope, :last_used_at, :created_at, :expires_at ])
  end

  def create
    unless current_agent.authenticate(params[:current_password].to_s)
      return render json: { error: "invalid_current_password" }, status: :unprocessable_entity
    end
    if current_agent.otp_required? &&
       (params[:otp_code].blank? || !Totp.valid?(current_agent.otp_secret, params[:otp_code]))
      return render json: { error: "otp_required" }, status: :unprocessable_entity
    end

    token, raw = ApiToken.issue(agent: current_agent, name: params.require(:name),
                                scope: params[:scope].presence || "read")
    render json: token.as_json(only: [ :id, :name, :scope, :expires_at ]).merge(token: raw), status: :created
  end

  def destroy
    current_agent.api_tokens.find(params[:id]).destroy!
    head :no_content
  end

  private

  def require_cookie_session_for_create
    return if request.headers["Authorization"].blank? && session[:agent_id].present?

    render json: { error: "cookie_session_required" }, status: :forbidden
  end
end
