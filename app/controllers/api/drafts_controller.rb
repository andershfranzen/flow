class Api::DraftsController < Api::BaseController
  # PUT /api/drafts — autosave, last-write-wins (B8)
  def upsert
    conversation = find_accessible_conversation!(params.require(:conversation_id))
    draft = current_agent.drafts.find_or_initialize_by(conversation: conversation)
    draft.mailbox_id = conversation.mailbox_id
    draft.update!(params.permit(:subject, :body, to: [], cc: []))
    render json: draft.as_json(only: [ :id, :conversation_id, :mailbox_id, :subject, :body, :to, :cc, :updated_at ])
  end

  def index
    render json: current_agent.drafts.order(updated_at: :desc)
                 .as_json(only: [ :id, :conversation_id, :mailbox_id, :subject, :body, :to, :cc, :updated_at ])
  end

  def destroy
    current_agent.drafts.find(params[:id]).destroy!
    head :no_content
  end
end
