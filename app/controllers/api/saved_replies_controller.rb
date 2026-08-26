class Api::SavedRepliesController < Api::BaseController
  def index
    replies = SavedReply.where(mailbox: nil).or(SavedReply.where(mailbox: current_agent.accessible_mailboxes))
    render json: replies.order(:name).as_json(only: [ :id, :name, :body, :mailbox_id ])
  end

  def create
    mailbox = mailbox_from_params
    return head :forbidden if mailbox.nil? && !current_agent.admin?

    reply = SavedReply.create!(params.permit(:name, :body).merge(mailbox_id: mailbox&.id))
    render json: reply.as_json(only: [ :id, :name, :body, :mailbox_id ]), status: :created
  end

  def update
    reply = SavedReply.find(params[:id])
    return head :forbidden if reply.mailbox.nil? && !current_agent.admin?
    raise ActiveRecord::RecordNotFound unless reply.mailbox.nil? || current_agent.can_access?(reply.mailbox)

    permitted = params.permit(:name, :body)
    if params.key?(:mailbox_id)
      mailbox = mailbox_from_params
      return head :forbidden if mailbox.nil? && !current_agent.admin?
      permitted[:mailbox_id] = mailbox&.id
    end
    reply.update!(permitted)
    render json: reply.as_json(only: [ :id, :name, :body, :mailbox_id ])
  end

  def destroy
    reply = SavedReply.find(params[:id])
    return head :forbidden if reply.mailbox.nil? && !current_agent.admin?
    raise ActiveRecord::RecordNotFound unless reply.mailbox.nil? || current_agent.can_access?(reply.mailbox)
    reply.destroy!
    head :no_content
  end

  # GET /api/saved_replies/:id/render?conversation_id= — variables filled (B9)
  def render_body
    reply = find_visible_reply!(params[:id])
    conversation = params[:conversation_id].present? ? find_accessible_conversation!(params[:conversation_id]) : nil
    render json: { body: reply.render(customer: conversation&.customer, agent: current_agent,
                                      mailbox: conversation&.mailbox) }
  end

  private

  def find_visible_reply!(id)
    reply = SavedReply.find(id)
    raise ActiveRecord::RecordNotFound unless reply.mailbox.nil? || current_agent.can_access?(reply.mailbox)
    reply
  end

  def mailbox_from_params
    params[:mailbox_id].present? ? find_accessible_mailbox!(params[:mailbox_id]) : nil
  end
end
