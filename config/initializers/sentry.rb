# Optional error tracking: set SENTRY_DSN and exceptions from web + jobs are
# reported. Without it this initializer is inert and Sentry never loads config.
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.breadcrumbs_logger = [ :active_support_logger ]
    config.send_default_pii = false # never ship email bodies or addresses
    config.traces_sample_rate = 0
  end
end
