ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# Load .env (written by bin/setup) so ad-hoc bin/rails commands see the same
# DATABASE_URL as bin/dev. Real environment variables always win, and
# FLOW_SKIP_DOTENV=1 ignores the file (e.g. to run the SQLite suite while
# .env points at PostgreSQL).
env_file = File.expand_path("../.env", __dir__)
if File.exist?(env_file) && ENV["FLOW_SKIP_DOTENV"].nil?
  File.readlines(env_file).each do |line|
    next if line.strip.empty? || line.lstrip.start_with?("#")
    key, value = line.strip.split("=", 2)
    ENV[key] ||= value if key && value
  end
end
