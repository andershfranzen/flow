class Api::NotificationsController < Api::BaseController
  def index
    notifications = current_agent.notifications.includes(conversation: :customer)
                                 .order(created_at: :desc).limit(50)
    render json: {
      unread: current_agent.notifications.unread.count,
      notifications: notifications.map { |n|
        n.as_json(only: [ :id, :kind, :read_at, :created_at ]).merge(
          conversation: n.conversation.as_json(only: [ :id, :number, :subject, :preview ]))
      }
    }
  end

  # POST /api/notifications/read — mark all (or ids) read
  def read
    scope = current_agent.notifications.unread
    scope = scope.where(id: params[:ids]) if params[:ids].present?
    scope.update_all(read_at: Time.current)
    head :no_content
  end
end
