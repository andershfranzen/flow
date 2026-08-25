# MCP tools (G4). The MCP client brings the model; these expose the inbox.
# server_context: { agent:, api_token: }
module McpTools
  module Helpers
    def agent(ctx) = ctx[:agent]

    def require_write!(ctx)
      token = ctx[:api_token]
      raise "write scope required" if token && !token.write?
    end

    def require_admin!(ctx)
      require_write!(ctx)
      raise "admin role required" unless agent(ctx).admin?
    end

    def find_mailbox!(address)
      Mailbox.find_by!(address: address.to_s.downcase.strip)
    end

    # MCP arguments arrive with symbol keys; models and slices want strings.
    def stringify(hash)
      (hash || {}).to_h.transform_keys(&:to_s)
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
      ids = SearchIndex.search(query)
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


  # ── Conversation actions beyond replying ─────────────────────────────────

  class SetStatus < MCP::Tool
    extend Helpers
    tool_name "set_status"
    description "Set a conversation's status: active, pending, closed, spam or trash. Optional snooze_until (ISO8601) snoozes it."
    input_schema(properties: { number: { type: "integer" }, status: { type: "string" },
                               snooze_until: { type: "string" } }, required: [ "number" ])

    def self.call(number:, status: nil, snooze_until: nil, server_context:)
      require_write!(server_context)
      c = find_conversation!(server_context, number)
      c.set_status!(status, agent: agent(server_context)) if status.present?
      c.update!(snoozed_until: Time.iso8601(snooze_until)) if snooze_until.present?
      text_response(conversation_summary(c.reload))
    end
  end

  class AddNote < MCP::Tool
    extend Helpers
    tool_name "add_note"
    description "Add an internal note to a conversation (never emailed to the customer)."
    input_schema(properties: { number: { type: "integer" }, body: { type: "string" } },
                 required: [ "number", "body" ])

    def self.call(number:, body:, server_context:)
      require_write!(server_context)
      c = find_conversation!(server_context, number)
      c.messages.create!(kind: "note", agent: agent(server_context), body_text: body)
      text_response({ number: c.number, note_added: true })
    end
  end

  class TagConversation < MCP::Tool
    extend Helpers
    tool_name "tag_conversation"
    description "Add or remove a tag on a conversation by tag name (tag is created if missing)."
    input_schema(properties: { number: { type: "integer" }, tag: { type: "string" },
                               remove: { type: "boolean" } }, required: [ "number", "tag" ])

    def self.call(number:, tag:, remove: false, server_context:)
      require_write!(server_context)
      c = find_conversation!(server_context, number)
      record = Tag.find_or_create_by!(name: tag.strip)
      remove ? c.tags.delete(record) : (c.tags << record unless c.tags.include?(record))
      text_response({ number: c.number, tags: c.tags.reload.map(&:name) })
    end
  end

  # ── Admin setup tools: everything needed to configure a fresh Flow ───────

  class ListAgents < MCP::Tool
    extend Helpers
    tool_name "list_agents"
    description "List all agents with role and mailbox access."
    input_schema(properties: {}, required: [])

    def self.call(server_context:)
      text_response(Agent.order(:name).map { |a|
        { email: a.email, name: a.name, role: a.role,
          mailboxes: a.admin? ? "all" : Mailbox.where(id: a.mailbox_ids).pluck(:address) }
      })
    end
  end

  class SaveAgent < MCP::Tool
    extend Helpers
    tool_name "save_agent"
    description "Create or update an agent by email (admin). Optional: name, role (user/admin), password, mailbox_addresses (replaces access; ignored for admins)."
    input_schema(properties: { email: { type: "string" }, name: { type: "string" },
                               role: { type: "string" }, password: { type: "string" },
                               mailbox_addresses: { type: "array", items: { type: "string" } } },
                 required: [ "email" ])

    def self.call(email:, name: nil, role: nil, password: nil, mailbox_addresses: nil, server_context:)
      require_admin!(server_context)
      a = Agent.find_or_initialize_by(email: email.downcase.strip)
      a.name = name if name.present?
      a.role = role if role.present?
      a.password = password if password.present?
      a.password = SecureRandom.hex(24) if a.new_record? && password.blank?
      a.name = a.email.split("@").first if a.name.blank?
      a.save!
      if mailbox_addresses.is_a?(Array) && !a.admin?
        ids = Mailbox.where(address: mailbox_addresses.map(&:downcase)).ids
        a.mailbox_accesses.where.not(mailbox_id: ids).destroy_all
        ids.each { |id| a.mailbox_accesses.find_or_create_by!(mailbox_id: id) }
      end
      text_response({ email: a.email, name: a.name, role: a.role,
                      mailboxes: a.admin? ? "all" : Mailbox.where(id: a.mailbox_ids).pluck(:address) })
    end
  end

  class SaveMailbox < MCP::Tool
    extend Helpers
    tool_name "save_mailbox"
    description "Create or update a mailbox by address (admin). Full IMAP/SMTP config: name, from_name, signature, auth_kind (password/microsoft/google), imap_host, imap_port, imap_ssl, imap_user, imap_password, imap_folder, smtp_host, smtp_port, smtp_security (starttls/ssl/none), smtp_user, smtp_password, auto_reply_enabled, auto_reply_body. OAuth mailboxes still need a human to click through the provider consent (Settings -> Mailboxes -> Connect)."
    input_schema(properties: { address: { type: "string" }, attributes: { type: "object", additionalProperties: true } },
                 required: [ "address" ])

    FIELDS = %w[name from_name signature auth_kind imap_host imap_port imap_ssl imap_user
                imap_password imap_folder smtp_host smtp_port smtp_security smtp_user
                smtp_password auto_reply_enabled auto_reply_body].freeze

    def self.call(address:, attributes: {}, server_context:)
      require_admin!(server_context)
      attributes = stringify(attributes)
      m = Mailbox.find_or_initialize_by(address: address.downcase.strip)
      m.name = address.split("@").first if m.new_record? && attributes["name"].blank?
      m.update!(attributes.slice(*FIELDS))
      text_response({ address: m.address, name: m.name, imap_configured: m.imap_configured?,
                      smtp_configured: m.smtp_configured?, auth_kind: m.auth_kind })
    end
  end

  class TestMailbox < MCP::Tool
    extend Helpers
    tool_name "test_mailbox"
    description "Test a mailbox's IMAP and SMTP connection (admin)."
    input_schema(properties: { address: { type: "string" } }, required: [ "address" ])

    def self.call(address:, server_context:)
      require_admin!(server_context)
      m = find_mailbox!(address)
      text_response({ address: m.address }.merge(m.connection_test))
    end
  end

  class SaveTeam < MCP::Tool
    extend Helpers
    tool_name "save_team"
    description "Create or update a team by name (admin). agent_emails replaces the member list. Teams round-robin via the workflow action assign_team."
    input_schema(properties: { name: { type: "string" },
                               agent_emails: { type: "array", items: { type: "string" } } },
                 required: [ "name" ])

    def self.call(name:, agent_emails: nil, server_context:)
      require_admin!(server_context)
      team = Team.find_or_create_by!(name: name.strip)
      if agent_emails.is_a?(Array)
        ids = Agent.where(email: agent_emails.map(&:downcase)).ids
        team.team_members.where.not(agent_id: ids).destroy_all
        ids.each { |id| team.team_members.find_or_create_by!(agent_id: id) }
      end
      text_response({ name: team.name, members: team.agents.reload.map(&:email) })
    end
  end

  class SaveTag < MCP::Tool
    extend Helpers
    tool_name "save_tag"
    description "Create or update a tag (write scope). color is a #rrggbb hex."
    input_schema(properties: { name: { type: "string" }, color: { type: "string" } }, required: [ "name" ])

    def self.call(name:, color: nil, server_context:)
      require_write!(server_context)
      tag = Tag.find_or_create_by!(name: name.strip)
      tag.update!(color: color) if color.present?
      text_response({ name: tag.name, color: tag.color })
    end
  end

  class SaveSavedReply < MCP::Tool
    extend Helpers
    tool_name "save_saved_reply"
    description "Create or update a saved reply by name (write scope). Supports {{customer.name}}, {{agent.name}}, {{mailbox.name}} variables. mailbox_address scopes it to one mailbox (omit = global)."
    input_schema(properties: { name: { type: "string" }, body: { type: "string" },
                               mailbox_address: { type: "string" } }, required: [ "name", "body" ])

    def self.call(name:, body:, mailbox_address: nil, server_context:)
      require_write!(server_context)
      reply = SavedReply.find_or_initialize_by(name: name.strip)
      reply.update!(body: body, mailbox_id: mailbox_address.present? ? find_mailbox!(mailbox_address).id : nil)
      text_response({ name: reply.name, mailbox: reply.mailbox&.address || "global" })
    end
  end

  class ListWebhooks < MCP::Tool
    extend Helpers
    tool_name "list_webhooks"
    description "List outbound webhooks (admin)."
    input_schema(properties: {}, required: [])

    def self.call(server_context:)
      require_admin!(server_context)
      text_response(Webhook.all.map { |w| { id: w.id, url: w.url, events: w.events, enabled: w.enabled } })
    end
  end

  class SaveWebhook < MCP::Tool
    extend Helpers
    tool_name "save_webhook"
    description "Create or update a webhook by url (admin). events subset of #{Webhook::EVENTS.join(', ')} (empty = all). Returns the signing secret on create."
    input_schema(properties: { url: { type: "string" }, events: { type: "array", items: { type: "string" } },
                               enabled: { type: "boolean" } }, required: [ "url" ])

    def self.call(url:, events: nil, enabled: true, server_context:)
      require_admin!(server_context)
      hook = Webhook.find_or_initialize_by(url: url)
      fresh = hook.new_record?
      hook.events = events if events.is_a?(Array)
      hook.enabled = enabled
      hook.save!
      text_response({ id: hook.id, url: hook.url, events: hook.events, enabled: hook.enabled,
                      secret: fresh ? hook.secret : "(unchanged — only shown on create)" })
    end
  end

  class ListWorkflows < MCP::Tool
    extend Helpers
    tool_name "list_workflows"
    description "List automation workflows (admin)."
    input_schema(properties: {}, required: [])

    def self.call(server_context:)
      require_admin!(server_context)
      text_response(Workflow.order(:position).map { |w|
        w.as_json(only: [ :id, :name, :enabled, :trigger, :match_type, :conditions, :actions, :runs_count ])
         .merge("mailbox" => w.mailbox_id && Mailbox.find_by(id: w.mailbox_id)&.address) })
    end
  end

  class SaveWorkflow < MCP::Tool
    extend Helpers
    tool_name "save_workflow"
    description "Create or update a workflow by name (admin). trigger: #{Workflow::TRIGGERS.join('/')}. conditions: [{field, operator, value}] with fields #{Workflow::CONDITION_FIELDS.join(', ')} and operators #{Workflow::OPERATORS.join(', ')}. actions: [{type, value}] with types #{Workflow::ACTION_TYPES.join(', ')}. match_type all/any. mailbox_address scopes it (omit = all mailboxes)."
    input_schema(properties: { name: { type: "string" }, trigger: { type: "string" },
                               match_type: { type: "string" }, enabled: { type: "boolean" },
                               mailbox_address: { type: "string" },
                               conditions: { type: "array", items: { type: "object", additionalProperties: true } },
                               actions: { type: "array", items: { type: "object", additionalProperties: true } } },
                 required: [ "name" ])

    def self.call(name:, trigger: nil, match_type: nil, enabled: true, mailbox_address: nil,
                  conditions: nil, actions: nil, server_context:)
      require_admin!(server_context)
      w = Workflow.find_or_initialize_by(name: name.strip)
      w.trigger = trigger if trigger.present?
      w.match_type = match_type if match_type.present?
      w.enabled = enabled
      w.mailbox_id = mailbox_address.present? ? find_mailbox!(mailbox_address).id : nil
      w.conditions = conditions.map { |c| stringify(c).slice("field", "operator", "value") } if conditions.is_a?(Array)
      w.actions = actions.map { |a| stringify(a).slice("type", "value") } if actions.is_a?(Array)
      w.position ||= (Workflow.maximum(:position) || 0) + 1
      w.save!
      text_response(w.as_json(only: [ :id, :name, :enabled, :trigger, :match_type, :conditions, :actions ]))
    end
  end

  class GetOrgSettings < MCP::Tool
    extend Helpers
    tool_name "get_org_settings"
    description "Read organisation settings (admin): site name, base URL, signatures, SSO, theme, OAuth app state. Secrets are never returned."
    input_schema(properties: {}, required: [])

    def self.call(server_context:)
      require_admin!(server_context)
      s = OrgSetting.current
      text_response(s.as_json(only: [ :site_name, :base_url, :notify_from, :default_signature,
                                      :ms_client_id, :ms_tenant, :google_client_id,
                                      :ms_sso_enabled, :sso_auto_provision, :sso_allowed_domains,
                                      :mcp_enabled ])
        .merge("theme" => s.theme || {}, "logo_set" => s.logo.attached?,
               "ms_client_secret_set" => s.ms_client_secret.present?,
               "google_client_secret_set" => s.google_client_secret.present?))
    end
  end

  class UpdateOrgSettings < MCP::Tool
    extend Helpers
    tool_name "update_org_settings"
    description "Update organisation settings (admin): site_name, base_url, notify_from, default_signature, ms_client_id, ms_client_secret, ms_tenant, google_client_id, google_client_secret, ms_sso_enabled, sso_auto_provision, sso_allowed_domains, theme (hex map with keys #{OrgSetting::THEME_KEYS.join(', ')})."
    input_schema(properties: { attributes: { type: "object", additionalProperties: true } },
                 required: [ "attributes" ])

    FIELDS = %w[site_name base_url notify_from default_signature ms_client_id ms_client_secret
                ms_tenant google_client_id google_client_secret ms_sso_enabled
                sso_auto_provision sso_allowed_domains crm_enabled crm_url].freeze

    def self.call(attributes:, server_context:)
      require_admin!(server_context)
      attributes = stringify(attributes)
      s = OrgSetting.current
      s.update!(attributes.slice(*FIELDS))
      if attributes["theme"].is_a?(Hash)
        s.update!(theme: stringify(attributes["theme"]).slice(*OrgSetting::THEME_KEYS)
                                            .select { |_k, v| v.to_s.match?(/\A#\h{6}\z/) })
      end
      GetOrgSettings.call(server_context: server_context)
    end
  end

  class ListPlugins < MCP::Tool
    extend Helpers
    tool_name "list_plugins"
    description "List installed plugins (admin)."
    input_schema(properties: {}, required: [])

    def self.call(server_context:)
      require_admin!(server_context)
      text_response(PluginRegistry.discover.map { |p|
        { name: p.name, enabled: p.enabled, loaded: p.loaded, error: p.error, version: p.manifest["version"] }
      })
    end
  end

  class SetPluginEnabled < MCP::Tool
    extend Helpers
    tool_name "set_plugin_enabled"
    description "Enable or disable an installed plugin (admin)."
    input_schema(properties: { name: { type: "string" }, enabled: { type: "boolean" } },
                 required: [ "name", "enabled" ])

    def self.call(name:, enabled:, server_context:)
      require_admin!(server_context)
      raise ActiveRecord::RecordNotFound unless PluginRegistry.valid_name?(name)
      PluginRegistry.set_enabled(name, enabled)
      text_response({ name: name, enabled: enabled })
    end
  end

  class CrmLookup < MCP::Tool
    extend Helpers
    tool_name "crm_lookup"
    description "Look up a person and their company in Microsoft Dynamics 365 CRM by email address."
    input_schema(properties: { email: { type: "string" } }, required: [ "email" ])

    def self.call(email:, server_context:)
      return text_response({ configured: false }) unless Crm.configured?
      text_response(Crm.lookup(email) || {})
    end
  end

  class Report < MCP::Tool
    extend Helpers
    tool_name "report"
    description "Support metrics for the last N days (admin): volumes, closes, first-reply time, per-agent and per-mailbox."
    input_schema(properties: { days: { type: "integer" } }, required: [])

    def self.call(days: 30, server_context:)
      require_admin!(server_context)
      text_response(Reports.summary(agent: agent(server_context), days: days))
    end
  end

  @registry = [ Search, GetThread, DraftReply, Send, ListMailboxes, Assign,
                SetStatus, AddNote, TagConversation,
                ListAgents, SaveAgent, SaveMailbox, TestMailbox, SaveTeam, SaveTag,
                SaveSavedReply, ListWebhooks, SaveWebhook, ListWorkflows, SaveWorkflow,
                GetOrgSettings, UpdateOrgSettings, ListPlugins, SetPluginEnabled,
                CrmLookup, Report ].map { |t| { tool: t, plugin: nil } }

  # Plugins add tools with McpTools.register(MyTool) — see docs/EXTENDING.md.
  # Tools registered while a plugin loads are tagged with it and disappear
  # from the server when the plugin is disabled.
  def self.register(tool)
    @registry << { tool: tool, plugin: PluginRegistry.loading } unless @registry.any? { |e| e[:tool] == tool }
  end

  def self.unregister(tool) = @registry.reject! { |e| e[:tool] == tool }

  def self.all
    @registry.select { |e| PluginRegistry.enabled?(e[:plugin]) }.map { |e| e[:tool] }
  end
end
