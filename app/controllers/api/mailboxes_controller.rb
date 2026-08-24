class Api::MailboxesController < Api::BaseController
  before_action :require_admin!, except: [ :index ]

  def index
    mailboxes = current_agent.accessible_mailboxes.order(:name)
    render json: mailboxes.map { |m| mailbox_json(m) }
  end

  def show
    render json: mailbox_json(Mailbox.find(params[:id]), full: true)
  end

  def create
    mailbox = Mailbox.create!(mailbox_params)
    render json: mailbox_json(mailbox, full: true), status: :created
  end

  def update
    mailbox = Mailbox.find(params[:id])
    mailbox.update!(mailbox_params)
    render json: mailbox_json(mailbox, full: true)
  end

  def destroy
    Mailbox.find(params[:id]).destroy!
    head :no_content
  end

  # POST /api/mailboxes/:id/test — try IMAP login and SMTP connect (A1).
  def test
    mailbox = Mailbox.find(params[:id])
    render json: { imap: try_imap(mailbox), smtp: try_smtp(mailbox) }
  end

  private

  def mailbox_params
    permitted = params.permit(:address, :name, :from_name, :signature, :auth_kind,
      :auto_reply_enabled, :auto_reply_body,
      :imap_host, :imap_port, :imap_ssl, :imap_user, :imap_password, :imap_folder,
      :smtp_host, :smtp_port, :smtp_user, :smtp_password, :smtp_security)
    # Blank password in the form means "keep the stored one".
    permitted.delete(:imap_password) if permitted[:imap_password].blank?
    permitted.delete(:smtp_password) if permitted[:smtp_password].blank?
    permitted
  end

  def try_imap(mailbox)
    return { ok: false, error: "not configured" } unless mailbox.imap_configured?
    imap = Net::IMAP.new(mailbox.imap_host, port: mailbox.imap_port, ssl: mailbox.imap_ssl)
    if mailbox.oauth?
      imap.authenticate("XOAUTH2", mailbox.imap_user, MailOauth.access_token!(mailbox))
    else
      imap.login(mailbox.imap_user, mailbox.imap_password)
    end
    imap.examine(mailbox.imap_folder)
    { ok: true }
  rescue StandardError => e
    { ok: false, error: e.message.truncate(200) }
  ensure
    imap&.disconnect rescue nil
  end

  def try_smtp(mailbox)
    return { ok: false, error: "not configured" } unless mailbox.smtp_configured?
    opts = mailbox.smtp_options
    smtp = Net::SMTP.new(opts[:address], opts[:port])
    smtp.enable_starttls_auto if opts[:enable_starttls_auto]
    smtp.enable_tls if opts[:tls]
    smtp.open_timeout = 5
    if opts[:user_name]
      smtp.start(opts[:domain], opts[:user_name], opts[:password], :plain) {}
    else
      smtp.start(opts[:domain]) {}
    end
    { ok: true }
  rescue StandardError => e
    { ok: false, error: e.message.truncate(200) }
  end

  def mailbox_json(m, full: false)
    json = m.as_json(only: [ :id, :address, :name, :from_name, :signature, :last_fetched_at, :fetch_error ])
    if full
      json.merge!(m.as_json(only: [ :imap_host, :imap_port, :imap_ssl, :imap_user, :imap_folder,
                                    :smtp_host, :smtp_port, :smtp_user, :smtp_security,
                                    :auth_kind, :auto_reply_enabled, :auto_reply_body ]))
      json["imap_password_set"] = m.imap_password.present?
      json["smtp_password_set"] = m.smtp_password.present?
      json["oauth_connected"] = m.oauth_connected?
    end
    json
  end
end
