return unless Rails.env.development?

agent = Agent.find_or_create_by!(email: "ahf@acmecool.com") do |record|
  record.name = "Anders Franzen"
  record.password = "development"
  record.role = "admin"
end

mailbox = Mailbox.find_or_initialize_by(address: "testai@acmecool.com")
mailbox.update!(name: "acmecool Support", from_name: "acmecool Support", auth_kind: "microsoft_app",
                imap_host: "outlook.office365.com", imap_port: 993, imap_ssl: true,
                imap_user: "testai@acmecool.com", imap_folder: "INBOX",
                smtp_host: "smtp.office365.com", smtp_port: 587, smtp_security: "starttls",
                smtp_user: "testai@acmecool.com")
MailboxAccess.find_or_create_by!(agent: agent, mailbox: mailbox)

org = OrgSetting.current
org.ms_client_secret = ENV["FLOW_MS_CLIENT_SECRET"] if ENV["FLOW_MS_CLIENT_SECRET"].present?
org.update!(site_name: "acmecool Support", base_url: "http://localhost:5173",
            ms_client_id: "00000000-0000-0000-0000-000000000000",
            ms_tenant: "00000000-0000-0000-0000-000000000000",
            ms_sso_enabled: org.ms_client_secret.present?, sso_auto_provision: true,
            sso_allowed_domains: "acmecool.com", default_signature: "Best regards, the Support team")

plugin = PluginState.find_or_create_by!(name: "flow-dgw-crm")
plugin_settings = plugin.settings_hash
plugin_settings["dgw_url"] = ENV.fetch("FLOW_DGW_URL", "https://datagateway.acmecool.local:8443")
plugin_settings["dgw_api_key"] = ENV["FLOW_DGW_API_KEY"] if ENV["FLOW_DGW_API_KEY"].present?
plugin_settings["crm_urls"] = ENV.fetch("FLOW_DGW_CRM_URLS", "DK=https://acmecool.crm4.dynamics.com,UK=https://acmecooluk.crm4.dynamics.com,BE=https://acmecoolbe.crm4.dynamics.com,CZ=https://acmecoolcz.crm4.dynamics.com,SK=https://acmecoolsk.crm4.dynamics.com,ES=https://acmecooles.crm4.dynamics.com,FR=https://acmecoolfr.crm4.dynamics.com,DE=https://acmecoolde.crm4.dynamics.com")
plugin.update!(enabled: true, settings: plugin_settings.to_json)

[
  [ "demo.customer@example.com", "Demo Customer", "[SIMULATED CRM TEST] Spare-parts request", "SIMULATED MESSAGE FOR FLOW / DYNAMICS 365 DEMO TESTING. This message was not sent by the customer. Please confirm availability of a replacement door gasket for our acmecool unit.", "active", nil, 2.hours.ago ],
  [ "demo.customer@example.com", "Demo Customer", "Demo: Cold room temperature alert", "The display on our acmecool cold room is showing 11 C and the compressor keeps stopping. Could you help us troubleshoot this today?", "active", nil, 1.hour.ago ],
  [ "ahf@acmecool.com", "Anders Haas Franzen", "Test", "Test", "active", nil, 1.day.ago ]
].each do |email, name, subject, body, status, assignee, sent_at|
  customer = Customer.find_or_create_by!(email: email) { |record| record.name = name }
  conversation = Conversation.find_or_create_by!(mailbox: mailbox, customer: customer) do |record|
    record.subject = subject
    record.status = status
    record.assignee = assignee
  end
  conversation.messages.find_or_create_by!(message_id_header: "<demo-#{customer.id}@flow.local>") do |message|
    message.kind = "inbound"
    message.status = "received"
    message.from_email = customer.email
    message.from_name = customer.name
    message.to = [ mailbox.address ]
    message.subject = subject
    message.body_text = body
    message.sent_at = sent_at
  end
end

puts org.ms_sso_enabled? ? "Development login: Microsoft (ahf@acmecool.com)" : "Development login: ahf@acmecool.com / development"
