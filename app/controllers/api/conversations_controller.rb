class Api::ConversationsController < Api::BaseController
  include HandlesUploads
  # GET /api/conversations?mailbox_id=&folder=&tag=&q=&page=
  def index
    if params[:mailbox_id]
      mailbox = find_accessible_mailbox!(params[:mailbox_id])
      scope = mailbox.conversations
    else
      scope = Conversation.where(mailbox: current_agent.accessible_mailboxes)
    end
    if params[:personal_folder_id].present?
      personal_folder = current_agent.personal_folders.find(params[:personal_folder_id])
      scope = scope.joins(:personal_folder_items)
                   .where(personal_folder_items: { personal_folder_id: personal_folder.id })
    else
      scope = scope.in_folder(params[:folder].presence || "all", current_agent)
    end
    scope = scope.joins(:tags).where(tags: { name: params[:tag] }) if params[:tag].present?
    scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    scope = scope.where(id: search_ids(params[:q])) if params[:q].present?
    order = params[:sort] == "oldest" ? { last_message_at: :asc, id: :asc } : { last_message_at: :desc, id: :desc }
    scope = scope.includes(:customer, :assignee, :tags).order(order)
    conversations = paginate(scope).to_a
    ids = conversations.map(&:id)
    reads = ConversationRead.where(agent: current_agent, conversation_id: ids)
                            .pluck(:conversation_id, :last_read_at).to_h
    my_stars = Star.where(agent: current_agent, conversation_id: ids).pluck(:conversation_id).to_set
    render json: { conversations: conversations.map { |c|
                     conversation_json(c).merge("unread" => unread?(c, reads[c.id]),
                                                "starred" => my_stars.include?(c.id)) },
                   folder_counts: folder_counts }
  end

  # PATCH /api/conversations/bulk { ids: [], status:|assignee_id:|starred: }
  def bulk
    ids = Array(params.require(:ids))
    updated = 0
    Conversation.where(id: ids).find_each do |conversation|
      next unless current_agent.can_access?(conversation.mailbox)
      if params.key?(:status)
        conversation.set_status!(params[:status], agent: current_agent)
        Notifier.status_changed(conversation)
      end
      if params.key?(:assignee_id)
        assignee = params[:assignee_id].present? ? Agent.find(params[:assignee_id]) : nil
        conversation.assign!(assignee, agent: current_agent)
        Notifier.assigned(conversation, by: current_agent) if assignee
      end
      set_starred(conversation, params[:starred]) if params.key?(:starred)
      if params[:remove_from_folder_id].present?
        current_agent.personal_folders.find_by(id: params[:remove_from_folder_id])
          &.personal_folder_items&.where(conversation_id: conversation.id)&.delete_all
      end
      updated += 1
    end
    render json: { updated: updated }
  end

  def show
    conversation = find_accessible_conversation!(params[:id])
    ConversationRead.upsert({ agent_id: current_agent.id, conversation_id: conversation.id,
                              last_read_at: Time.current, created_at: Time.current, updated_at: Time.current },
                            unique_by: [ :agent_id, :conversation_id ])
    render json: conversation_json(conversation, full: true)
  end

  # POST /api/conversations — agent starts a new outbound conversation (B17).
  # Accepts assignee_id (defaults to the author), an initial status, Cc/Bcc,
  # attachments and inline images — the full composer, not a toy form.
  def create
    mailbox = find_accessible_mailbox!(params.require(:mailbox_id))
    to = Array(params.require(:to)).map(&:to_s).reject(&:blank?)
    raise ActionController::ParameterMissing, :to if to.empty?
    assignee =
      if params[:assignee_id].present?
        candidate = Agent.find(params[:assignee_id])
        candidate.can_access?(mailbox) ? candidate : current_agent
      else
        current_agent
      end
    customer = Customer.for_email(to.first)
    conversation = nil
    message = nil
    Conversation.transaction do
      conversation = Conversation.create!(
        mailbox: mailbox, customer: customer, subject: params[:subject].to_s,
        assignee: assignee, last_message_at: Time.current
      )
      message = conversation.messages.create!(
        kind: "outbound", status: "queued", agent: current_agent,
        to: to, cc: Array(params[:cc]).map(&:to_s).reject(&:blank?),
        bcc: Array(params[:bcc]).map(&:to_s).reject(&:blank?),
        body_text: params[:body_text].to_s,
        body_html: HtmlSanitizer.call(append_signature(params[:body_html].to_s, mailbox))
      )
      rewrite_inline_cids!(message, attach_uploads(message))
    end
    if params[:status].present? && Conversation::STATUSES.include?(params[:status]) && params[:status] != "active"
      conversation.set_status!(params[:status], agent: current_agent)
    end
    SendMessageJob.set(wait: 15.seconds).perform_later(message)
    render json: conversation_json(conversation, full: true), status: :created
  end

  # POST /api/conversations/:id/merge { into_number } — merge :id into the target (B14)
  def merge
    source = find_accessible_conversation!(params[:id])
    target = Conversation.find_by!(number: params.require(:into_number))
    raise ActiveRecord::RecordNotFound unless current_agent.can_access?(source.mailbox)
    if source.id == target.id || source.merged_into_id || target.merged_into_id
      return render json: { error: "cannot_merge" }, status: :unprocessable_entity
    end
    Conversation.transaction do
      source.messages.update_all(conversation_id: target.id)
      source.events.update_all(conversation_id: target.id)
      source.notifications.update_all(conversation_id: target.id)
      source.drafts.destroy_all
      target.tag_ids |= source.tag_ids
      source.conversation_tags.destroy_all
      SearchIndex.reassign(source.id, target.id)
      source.update!(merged_into_id: target.id, status: "closed", assignee: nil)
      Conversation.reset_counters(source.id, :messages)
      Conversation.reset_counters(target.id, :messages)
      last = target.messages.order(:created_at).last
      target.update_columns(last_message_at: last&.created_at,
                            preview: last&.body_text.to_s.gsub(/\s+/, " ").strip.truncate(140))
      target.events.create!(agent: current_agent, kind: "merged", data: { from_number: source.number })
    end
    render json: conversation_json(target.reload, full: true)
  end

  # POST /api/conversations/:id/presence — viewing heartbeat (B12).
  # Lives here (not the Live streaming controller) so heartbeats never touch
  # ActionController::Live's thread machinery.
  def presence
    conversation = find_accessible_conversation!(params[:id])
    viewers = Presence.heartbeat(conversation.id, current_agent).reject { |v| v["id"] == current_agent.id }
    render json: { viewers: viewers }
  end

  # POST/DELETE /api/conversations/:id/follow — notify me even when not assignee (B11)
  def follow
    conversation = find_accessible_conversation!(params[:id])
    Follower.find_or_create_by!(agent: current_agent, conversation: conversation)
    render json: { followed: true }
  end

  def unfollow
    conversation = find_accessible_conversation!(params[:id])
    Follower.where(agent: current_agent, conversation: conversation).destroy_all
    render json: { followed: false }
  end

  # PATCH /api/conversations/:id — status, star, assignee, tags, mailbox (B4/B5/B10/B11/B15)
  def update
    conversation = find_accessible_conversation!(params[:id])
    if params.key?(:mailbox_id) && params[:mailbox_id].to_i != conversation.mailbox_id
      new_mailbox = find_accessible_mailbox!(params[:mailbox_id])
      old_name = conversation.mailbox.name
      conversation.update!(mailbox: new_mailbox)
      conversation.events.create!(agent: current_agent, kind: "moved",
                                  data: { from: old_name, to: new_mailbox.name })
    end
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
    set_starred(conversation, params[:starred]) if params.key?(:starred)
    if params.key?(:snooze_until)
      conversation.update!(snoozed_until: params[:snooze_until].presence)
    end
    if params.key?(:tag_ids)
      conversation.tag_ids = Array(params[:tag_ids])
    end
    render json: conversation_json(conversation.reload, full: true)
  end

  private

  def search_ids(q)
    ids = SearchIndex.search(q)
    customer_ids = Customer.where("email LIKE :q OR name LIKE :q", q: "%#{q}%").ids
    ids | Conversation.where(customer_id: customer_ids).ids
  end

  def folder_counts
    base = params[:mailbox_id] ? Mailbox.find(params[:mailbox_id]).conversations : Conversation.where(mailbox: current_agent.accessible_mailboxes)
    open = base.where(status: %w[active pending])
    { unassigned: open.where(assignee_id: nil).count,
      mine: open.where(assignee_id: current_agent.id).count,
      assigned: open.where.not(assignee_id: nil).count,
      starred: base.joins(:stars).where(stars: { agent_id: current_agent.id }).where.not(status: %w[spam trash]).count,
      closed: base.where(status: "closed").count,
      spam: base.where(status: "spam").count,
      trash: base.where(status: "trash").count,
      snoozed: base.where(status: %w[active pending]).snoozed.count,
      drafts: current_agent.drafts.count }
  end

  # Stars are personal (D-layer): toggle for the current agent only.
  def set_starred(conversation, value)
    if ActiveModel::Type::Boolean.new.cast(value)
      Star.find_or_create_by!(agent: current_agent, conversation: conversation)
    else
      Star.where(agent: current_agent, conversation: conversation).delete_all
    end
  end

  def unread?(conversation, last_read_at)
    return false if conversation.last_message_at.nil?
    last_read_at.nil? || conversation.last_message_at > last_read_at
  end

  # Everyone on the thread except our own mailbox address (display + reply-all).
  def participants(c)
    seen = {}
    c.messages.each do |m|
      seen[m.from_email.downcase] ||= m.from_name if m.from_email.present?
      (Array(m.to) + Array(m.cc)).each do |raw|
        email = raw[/[^\s<>,;"']+@[^\s<>,;"']+/].to_s.downcase
        seen[email] ||= nil if email.present?
      end
    end
    seen.reject { |email, _| c.mailbox.matches_address?(email) }
        .map { |email, name| { email: email, name: name } }
  end

  # Prefill for the composer: reply-all from the last inbound message.
  def reply_all_defaults(c)
    last = c.messages.where(kind: "inbound").order(:created_at).last
    return { to: [ c.customer.email ], cc: [] } unless last
    to = [ last.from_email.to_s.downcase ].reject(&:blank?)
    to = [ c.customer.email ] if to.empty?
    cc = (Array(last.to) + Array(last.cc))
         .map { |raw| raw[/[^\s<>,;"']+@[^\s<>,;"']+/].to_s.downcase }
         .reject(&:blank?).uniq
    cc -= to
    cc = cc.reject { |email| c.mailbox.matches_address?(email) }
    { to: to, cc: cc }
  end

  def append_signature(html, mailbox)
    signature = current_agent.signature.presence || mailbox.signature.presence ||
                OrgSetting.current.default_signature
    return html if signature.blank? || params[:skip_signature].present?
    "#{html}<br><br>--<br>#{signature}"
  end

  def conversation_json(c, full: false)
    json = c.as_json(only: [ :id, :number, :subject, :status, :preview,
                             :messages_count, :last_message_at, :mailbox_id, :created_at, :snoozed_until ])
    json["starred"] = c.stars.loaded? ? c.stars.any? { |s| s.agent_id == current_agent.id } : c.stars.exists?(agent_id: current_agent.id)
    json["customer"] = c.customer.as_json(only: [ :id, :email, :name ])
    json["assignee"] = c.assignee&.as_json(only: [ :id, :name ])
    json["tags"] = c.tags.map { |t| t.as_json(only: [ :id, :name, :color ]) }
    json["merged_into_id"] = c.merged_into_id
    if full
      json["messages"] = c.messages.with_attached_files.includes(:agent).order(:created_at).map { |m| message_json(m) }
      json["participants"] = participants(c)
      json["reply_all"] = reply_all_defaults(c)
      json["followed"] = c.followers.exists?(agent_id: current_agent.id)
      json["personal_folder_ids"] = current_agent.personal_folders.joins(:personal_folder_items)
                                                 .where(personal_folder_items: { conversation_id: c.id }).ids
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
