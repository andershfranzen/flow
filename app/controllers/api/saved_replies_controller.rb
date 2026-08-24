class Api::SavedRepliesController < Api::BaseController
  def index
    replies = SavedReply.where(mailbox: nil).or(SavedReply.where(mailbox: current_agent.accessible_mailboxes))
    render json: replies.order(:name).as_json(only: [ :id, :name, :body, :mailbox_id ])
  end

  def create
    reply = SavedReply.create!(params.permit(:name, :body, :mailbox_id))
    render json: reply.as_json(only: [ :id, :name, :body, :mailbox_id ]), status: :created
  end

  def update
    reply = SavedReply.find(params[:id])
    reply.update!(params.permit(:name, :body, :mailbox_id))
    render json: reply.as_json(only: [ :id, :name, :body, :mailbox_id ])
  end

  def destroy
    SavedReply.find(params[:id]).destroy!
    head :no_content
  end

  # GET /api/saved_replies/:id/render?conversation_id= — variables filled (B9)
  def render_body
    reply = SavedReply.find(params[:id])
    conversation = params[:conversation_id].present? ? find_accessible_conversation!(params[:conversation_id]) : nil
    render json: { body: reply.render(customer: conversation&.customer, agent: current_agent,
                                      mailbox: conversation&.mailbox) }
  end
end
