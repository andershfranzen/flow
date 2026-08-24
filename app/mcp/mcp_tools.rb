# MCP tools (G4). The MCP client brings the model; these expose the inbox.
# server_context: { agent:, api_token: }
module McpTools
  module Helpers
    def agent(ctx) = ctx[:agent]

    def require_write!(ctx)
      token = ctx[:api_token]
      raise "write scope required" if token && !token.write?
    end

    def find_conversation!(ctx, number)
      conversation = Conversation.find_by!(number: number)
      raise ActiveRecord::RecordNotFound unless agent(ctx).can_access?(conversation.mailbox)
      conversation
    end

    def text_response(data)
      MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
    end

    def conversation_summary(c)
      { number: c.number, subject: c.subject, status: c.status, mailbox: c.mailbox.address,
        customer: c.customer.email, assignee: c.assignee&.name, preview: c.preview,
        last_message_at: c.last_message_at }
    end
  end

  class Search < MCP::Tool
    extend Helpers
    tool_name "search"
    description "Search conversations by full-text query. Returns matching conversations with numbers."
    input_schema(properties: { query: { type: "string" } }, required: [ "query" ])

    def self.call(query:, server_context:)
      sql = ActiveRecord::Base.sanitize_sql(
        [ "SELECT DISTINCT conversation_id FROM message_search WHERE message_search MATCH ?",
          query.split.map { |t| "\"#{t.delete('"')}\"" }.join(" ") ]
      )
      ids = ActiveRecord::Base.connection.select_values(sql) rescue []
      conversations = Conversation.where(id: ids, mailbox: agent(server_context).accessible_mailboxes)
                                  .order(last_message_at: :desc).limit(25)
      text_response(conversations.map { |c| conversation_summary(c) })
    end
  end

  class GetThread < MCP::Tool
    extend Helpers
    tool_name "get_thread"
    description "Get a conversation transcript by its number (e.g. 142). Notes are internal."
    input_schema(properties: { number: { type: "integer" } }, required: [ "number" ])

    def self.call(number:, server_context:)
      c = find_conversation!(server_context, number)
      text_response(conversation_summary(c).merge(
        messages: c.messages.order(:created_at).map { |m|
          { kind: m.kind, from: m.from_email || m.agent&.name, at: m.created_at,
            text: m.body_text.to_s.truncate(4000) }
        }))
    end
  end

  class DraftReply < MCP::Tool
    extend Helpers
    tool_name "draft_reply"
    description "Save a reply draft on a conversation for human review. Returns thread context. Does not send."
    input_schema(properties: { number: { type: "integer" }, body: { type: "string" } },
                 required: [ "number" ])

    def self.call(number:, body: nil, server_context:)
      c = find_conversation!(server_context, number)
      if body.present?
        require_write!(server_context)
        draft = agent(server_context).drafts.find_or_initialize_by(conversation_id: c.id)
        draft.update!(body: body, mailbox_id: c.mailbox_id, to: [ c.customer.email ])
      end
      text_response(conversation_summary(c).merge(
        draft_saved: body.present?,
        signature: c.mailbox.signature.to_s,
        last_customer_message: c.messages.where(kind: "inbound").last&.body_text.to_s.truncate(4000)))
    end
  end

  class Send < MCP::Tool
    extend Helpers
    tool_name "send"
    description "Send a reply on a conversation to the customer. Queues real outbound email."
    input_schema(properties: { number: { type: "integer" }, body: { type: "string" } },
                 required: [ "number", "body" ])

    def self.call(number:, body:, server_context:)
      require_write!(server_context)
      c = find_conversation!(server_context, number)
      message = c.messages.create!(
        kind: "outbound", status: "queued", agent: agent(server_context),
        to: [ c.customer.email ], body_text: body
      )
      SendMessageJob.perform_later(message)
      agent(server_context).drafts.where(conversation: c).destroy_all
      text_response({ queued: true, message_id: message.id, to: message.to })
    end
  end

  class ListMailboxes < MCP::Tool
    extend Helpers
    tool_name "list_mailboxes"
    description "List mailboxes this token can access."
    input_schema(properties: {}, required: [])

    def self.call(server_context:)
      text_response(agent(server_context).accessible_mailboxes.map { |m|
        { id: m.id, address: m.address, name: m.name }
      })
    end
  end

  class Assign < MCP::Tool
    extend Helpers
    tool_name "assign"
    description "Assign a conversation to an agent by email (empty email unassigns)."
    input_schema(properties: { number: { type: "integer" }, agent_email: { type: "string" } },
                 required: [ "number" ])

    def self.call(number:, agent_email: nil, server_context:)
      require_write!(server_context)
      c = find_conversation!(server_context, number)
      assignee = agent_email.present? ? Agent.find_by!(email: agent_email) : nil
      c.assign!(assignee, agent: agent(server_context))
      Notifier.assigned(c, by: agent(server_context)) if assignee
      text_response({ number: c.number, assignee: assignee&.name })
    end
  end

  ALL = [ Search, GetThread, DraftReply, Send, ListMailboxes, Assign ].freeze
end
