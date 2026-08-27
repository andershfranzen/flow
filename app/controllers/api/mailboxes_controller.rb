class Api::MailboxesController < Api::BaseController
  before_action :require_admin!, except: [ :index ]

  def index
    mailboxes = current_agent.accessible_mailboxes.order(:name)
    waiting = Conversation.where(mailbox: mailboxes, status: %w[active pending], assignee_id: nil)
                          .not_snoozed.group(:mailbox_id).count
    render json: mailboxes.map { |m| mailbox_json(m).merge("unassigned_count" => waiting[m.id] || 0) }
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
    render json: mailbox.connection_test
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

  def mailbox_json(m, full: false)
    json = m.as_json(only: [ :id, :address, :name, :from_name, :signature, :last_fetched_at, :fetch_error ])
    json["signature"] = HtmlSanitizer.call(m.signature)
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
