class Api::CustomersController < Api::BaseController
  def show
    customer = Customer.find(params[:id])
    conversations = customer.conversations.where(mailbox: current_agent.accessible_mailboxes)
                            .order(last_message_at: :desc).limit(50)
    render json: customer.as_json(only: [ :id, :email, :name, :emails, :phones, :created_at ])
                         .merge(conversations: conversations.map { |c|
                           c.as_json(only: [ :id, :number, :subject, :status, :preview, :last_message_at ])
                         })
  end

  def update
    customer = Customer.find(params[:id])
    customer.update!(params.permit(:name))
    render json: customer.as_json(only: [ :id, :email, :name ])
  end
end
