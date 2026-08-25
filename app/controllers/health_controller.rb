# GET /health — db + last successful fetch per mailbox (F3).
class HealthController < ActionController::Base
  def show
    db_ok = ActiveRecord::Base.connection.select_value("SELECT 1") == 1
    mailboxes = Mailbox.all.map do |m|
      { address: m.address, last_fetched_at: m.last_fetched_at, fetch_error: m.fetch_error }
    end
    render json: { ok: db_ok, mailboxes: mailboxes, queue: queue_stats },
           status: db_ok ? :ok : :service_unavailable
  rescue StandardError => e
    render json: { ok: false, error: e.class.name }, status: :service_unavailable
  end

  private

  # "Mail silently stopped sending" must be visible from the outside (F3).
  def queue_stats
    oldest = SolidQueue::ReadyExecution.minimum(:created_at)
    { pending: SolidQueue::ReadyExecution.count,
      failed: SolidQueue::FailedExecution.count,
      oldest_pending_seconds: oldest && (Time.current - oldest).round }
  rescue StandardError
    nil # queue db not reachable from this process
  end
end
