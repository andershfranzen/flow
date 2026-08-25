class Api::CustomersController < Api::BaseController
  def show
    show_target(Customer.find(params[:id]))
  end

  def update
    customer = Customer.find(params[:id])
    permitted = params.permit(:name, :company, :notes, phones: [])
    permitted[:phones] = Array(params[:phones]).grep(String).reject(&:blank?) if params.key?(:phones)
    customer.update!(permitted)
    render json: customer.as_json(only: [ :id, :email, :name, :company, :notes, :phones ])
  end

  # POST /api/customers/:id/merge { source_email } — the other identity folds in (C7)
  def merge
    target = Customer.find(params[:id])
    source = Customer.find_by!(email: params.require(:source_email).to_s.downcase.strip)
    if source.id == target.id
      return render json: { error: "same_customer" }, status: :unprocessable_entity
    end
    Customer.transaction do
      Conversation.where(customer_id: source.id).update_all(customer_id: target.id)
      target.update!(
        emails: (target.emails + [ source.email ] + source.emails).uniq,
        phones: (target.phones + source.phones).uniq,
        name: target.name.presence || source.name,
        company: target.company.presence || source.company
      )
      source.reload.destroy!
    end
    show_target(target)
  end

  private

  def show_target(customer)
    conversations = customer.conversations.where(mailbox: current_agent.accessible_mailboxes)
                            .order(last_message_at: :desc).limit(50)
    render json: customer.as_json(only: [ :id, :email, :name, :emails, :phones, :company, :notes, :created_at ])
                         .merge(conversations: conversations.map { |c|
                           c.as_json(only: [ :id, :number, :subject, :status, :preview, :last_message_at ])
                         })
  end
end
