# GET /health — db + last successful fetch per mailbox (F3).
class HealthController < ActionController::Base
  before_action :require_health_token!

  def show
    db_ok = ActiveRecord::Base.connection.select_value("SELECT 1") == 1
    mailboxes = Mailbox.all.map do |m|
      stale = m.imap_configured? &&
              (m.fetch_error.present? || m.last_fetched_at.nil? || m.last_fetched_at < 15.minutes.ago)
      { address: m.address, last_fetched_at: m.last_fetched_at, fetch_error: m.fetch_error, stale: stale }
    end
    render json: { ok: db_ok, warnings: mailboxes.count { |m| m[:stale] },
                   mailboxes: mailboxes, queue: queue_stats },
           status: db_ok ? :ok : :service_unavailable
  rescue StandardError => e
    render json: { ok: false, error: e.class.name }, status: :service_unavailable
  end

  private

  def require_health_token!
    expected = ENV["FLOW_HEALTH_TOKEN"].to_s
    provided = request.headers["Authorization"].to_s.match(/\ABearer (.+)\z/)&.[](1)
    return head :unauthorized unless expected.present? && provided.present?
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, provided)
  end

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
