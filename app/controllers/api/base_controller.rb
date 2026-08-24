class Api::BaseController < ApplicationController
  before_action :require_agent!
  before_action :require_write_scope!

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end
  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: "invalid", details: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def touch_last_seen
    current_agent.update_column(:last_seen_at, Time.current) if current_agent
  end

  def find_accessible_mailbox!(id)
    mailbox = Mailbox.find(id)
    raise ActiveRecord::RecordNotFound unless current_agent.can_access?(mailbox)
    mailbox
  end

  def find_accessible_conversation!(id)
    conversation = Conversation.find(id)
    raise ActiveRecord::RecordNotFound unless current_agent.can_access?(conversation.mailbox)
    conversation
  end

  def paginate(scope)
    page = [ params.fetch(:page, 1).to_i, 1 ].max
    per = params.fetch(:per_page, 50).to_i.clamp(1, 200)
    scope.offset((page - 1) * per).limit(per)
  end
end
