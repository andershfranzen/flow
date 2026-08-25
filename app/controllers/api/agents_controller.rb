class Api::AgentsController < Api::BaseController
  before_action :require_admin!, except: [ :index, :me, :update_me ]

  def index
    render json: Agent.order(:name).map { |a| agent_json(a) }
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
    permitted = params.permit(:name, :password, :locale, :timezone, :signature, notify_prefs: {}, muted_mailbox_ids: [])
    permitted.reject! { |k, v| v.blank? && !%w[muted_mailbox_ids signature].include?(k) }
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
         .merge(notify_prefs: agent.notify_prefs, mailbox_ids: agent.mailbox_ids,
                muted_mailbox_ids: agent.muted_mailbox_ids)
  end
end
