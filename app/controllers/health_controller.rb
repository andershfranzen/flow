# GET /health — db + last successful fetch per mailbox (F3).
class HealthController < ActionController::Base
  def show
    db_ok = ActiveRecord::Base.connection.select_value("SELECT 1") == 1
    mailboxes = Mailbox.all.map do |m|
      { address: m.address, last_fetched_at: m.last_fetched_at, fetch_error: m.fetch_error }
    end
    render json: { ok: db_ok, mailboxes: mailboxes }, status: db_ok ? :ok : :service_unavailable
  rescue StandardError => e
    render json: { ok: false, error: e.class.name }, status: :service_unavailable
  end
end
