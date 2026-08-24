class Api::ConversationsController < Api::BaseController
  # GET /api/conversations?mailbox_id=&folder=&tag=&q=&page=
  def index
    if params[:mailbox_id]
      mailbox = find_accessible_mailbox!(params[:mailbox_id])
      scope = mailbox.conversations
    else
      scope = Conversation.where(mailbox: current_agent.accessible_mailboxes)
    end
    scope = scope.in_folder(params[:folder].presence || "all", current_agent)
    scope = scope.joins(:tags).where(tags: { name: params[:tag] }) if params[:tag].present?
    scope = scope.where(id: search_ids(params[:q])) if params[:q].present?
    scope = scope.includes(:customer, :assignee, :tags).order(last_message_at: :desc, id: :desc)
    render json: { conversations: paginate(scope).map { |c| conversation_json(c) },
                   folder_counts: folder_counts }
  end

  def show
    conversation = find_accessible_conversation!(params[:id])
    render json: conversation_json(conversation, full: true)
  end

  # POST /api/conversations — agent starts a new outbound conversation (B17)
  def create
    mailbox = find_accessible_mailbox!(params.require(:mailbox_id))
    to = Array(params.require(:to)).map(&:to_s)
    customer = Customer.for_email(to.first)
    conversation = nil
    Conversation.transaction do
      conversation = Conversation.create!(
        mailbox: mailbox, customer: customer, subject: params[:subject].to_s,
        assignee: current_agent, last_message_at: Time.current
      )
      message = conversation.messages.create!(
        kind: "outbound", status: "queued", agent: current_agent,
        to: to, cc: Array(params[:cc]).map(&:to_s),
        body_text: params[:body_text].to_s,
        body_html: HtmlSanitizer.call(append_signature(params[:body_html].to_s, mailbox))
      )
      SendMessageJob.perform_later(message)
    end
    render json: conversation_json(conversation, full: true), status: :created
  end

  # PATCH /api/conversations/:id — status, star, assignee, tags (B4/B5/B10/B11)
  def update
    conversation = find_accessible_conversation!(params[:id])
    if params.key?(:status)
      conversation.set_status!(params[:status], agent: current_agent)
      Notifier.status_changed(conversation)
    end
    if params.key?(:assignee_id)
      assignee = params[:assignee_id].present? ? Agent.find(params[:assignee_id]) : nil
      raise ActiveRecord::RecordNotFound if assignee && !assignee.can_access?(conversation.mailbox)
      conversation.assign!(assignee, agent: current_agent)
      Notifier.assigned(conversation, by: current_agent)
    end
    conversation.update!(starred: params[:starred]) if params.key?(:starred)
    if params.key?(:tag_ids)
      conversation.tag_ids = Array(params[:tag_ids])
    end
    render json: conversation_json(conversation.reload, full: true)
  end

  private

  def search_ids(q)
    sql = ActiveRecord::Base.sanitize_sql(
      [ "SELECT DISTINCT conversation_id FROM message_search WHERE message_search MATCH ?", fts_quote(q) ]
    )
    ids = ActiveRecord::Base.connection.select_values(sql)
    customer_ids = Customer.where("email LIKE :q OR name LIKE :q", q: "%#{q}%").ids
    ids | Conversation.where(customer_id: customer_ids).ids
  rescue ActiveRecord::StatementInvalid
    [] # bad FTS syntax from user input is not an error
  end

  def fts_quote(q)
    q.split.map { |t| "\"#{t.delete('"')}\"" }.join(" ")
  end

  def folder_counts
    base = params[:mailbox_id] ? Mailbox.find(params[:mailbox_id]).conversations : Conversation.where(mailbox: current_agent.accessible_mailboxes)
    open = base.where(status: %w[active pending])
    { unassigned: open.where(assignee_id: nil).count,
      mine: open.where(assignee_id: current_agent.id).count,
      assigned: open.where.not(assignee_id: nil).count,
      starred: base.where(starred: true).where.not(status: %w[spam trash]).count,
      closed: base.where(status: "closed").count,
      spam: base.where(status: "spam").count,
      trash: base.where(status: "trash").count,
      drafts: current_agent.drafts.count }
  end

  def append_signature(html, mailbox)
    return html if mailbox.signature.blank?
    "#{html}<br><br>--<br>#{mailbox.signature}"
  end

  def conversation_json(c, full: false)
    json = c.as_json(only: [ :id, :number, :subject, :status, :preview, :starred,
                             :messages_count, :last_message_at, :mailbox_id, :created_at ])
    json["customer"] = c.customer.as_json(only: [ :id, :email, :name ])
    json["assignee"] = c.assignee&.as_json(only: [ :id, :name ])
    json["tags"] = c.tags.map { |t| t.as_json(only: [ :id, :name, :color ]) }
    if full
      json["messages"] = c.messages.with_attached_files.includes(:agent).order(:created_at).map { |m| message_json(m) }
      json["events"] = c.events.order(:created_at).map { |e|
        e.as_json(only: [ :id, :kind, :data, :created_at ]).merge("agent" => e.agent&.as_json(only: [ :id, :name ]))
      }
      json["viewers"] = Presence.viewers(c.id).reject { |v| v["id"] == current_agent.id }
    end
    json
  end

  def message_json(m)
    m.as_json(only: [ :id, :kind, :status, :from_email, :from_name, :to, :cc,
                      :body_text, :body_html, :bounce, :auto_submitted, :sent_at, :created_at ])
     .merge(
       "agent" => m.agent&.as_json(only: [ :id, :name ]),
       "attachments" => m.files.map { |f|
         { id: f.id, filename: f.filename.to_s, content_type: f.content_type,
           byte_size: f.byte_size, content_id: f.blob.metadata["content_id"],
           url: "/api/attachments/#{f.id}" }
       })
  end
end
