class Api::AgentsController < Api::BaseController
  before_action :require_admin!, except: [ :index, :me, :update_me ]

  def index
    render json: Agent.order(:name).map { |a| current_agent.admin? ? agent_json(a) : agent_summary(a) }
  end

  def create
    agent = Agent.create!(agent_params)
    set_mailbox_access(agent)
    render json: agent_json(agent), status: :created
  end

  def update
    agent = Agent.find(params[:id])
    agent.update!(agent_params)
    set_mailbox_access(agent)
    render json: agent_json(agent)
  end

  def destroy
    agent = Agent.find(params[:id])
    return render json: { error: "cannot_delete_self" }, status: :unprocessable_entity if agent == current_agent
    agent.destroy!
    head :no_content
  end

  # PATCH /api/me — own profile + notify prefs (H9)
  def update_me
    permitted = params.permit(:name, :password, :locale, :timezone, :signature, notify_prefs: {}, ui_prefs: {}, muted_mailbox_ids: [])
    permitted.reject! { |k, v| v.blank? && !%w[muted_mailbox_ids signature ui_prefs].include?(k) }
    if permitted[:password].present? && !current_agent.authenticate(params[:current_password].to_s)
      return render json: { error: "invalid_current_password" }, status: :unprocessable_entity
    end
    if permitted[:password].present? && current_agent.otp_required? &&
       (params[:otp_code].blank? || !Totp.valid?(current_agent.otp_secret, params[:otp_code]))
      return render json: { error: "otp_required" }, status: :unprocessable_entity
    end
    current_agent.update!(permitted)
    session[:session_token] = current_agent.session_token # survive own password change
    render json: agent_json(current_agent)
  end

  def me
    render json: agent_json(current_agent)
  end

  private

  def agent_params
    permitted = params.permit(:email, :name, :password, :role, :locale, :timezone)
    permitted.delete(:password) if permitted[:password].blank?
    permitted
  end

  def set_mailbox_access(agent)
    return unless params[:mailbox_ids].is_a?(Array)
    agent.mailbox_accesses.where.not(mailbox_id: params[:mailbox_ids]).destroy_all
    params[:mailbox_ids].each { |id| agent.mailbox_accesses.find_or_create_by!(mailbox_id: id) }
  end

  def agent_json(agent)
    agent.as_json(only: [ :id, :email, :name, :role, :locale, :timezone, :signature, :otp_required, :last_seen_at ])
         .merge("signature" => HtmlSanitizer.call(agent.signature),
                notify_prefs: agent.notify_prefs, ui_prefs: agent.ui_prefs || {},
                mailbox_ids: agent.mailbox_ids, muted_mailbox_ids: agent.muted_mailbox_ids)
  end

  def agent_summary(agent)
    agent.as_json(only: [ :id, :email, :name ])
  end
end
