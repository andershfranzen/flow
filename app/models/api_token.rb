class ApiToken < ApplicationRecord
  SCOPES = %w[read write].freeze
  belongs_to :agent
  validates :name, presence: true
  validates :scope, inclusion: { in: SCOPES }

  # Returns [record, raw_token]; raw is shown once, only the SHA-256 lands at rest (G2).
  def self.issue(agent:, name:, scope: "read")
    raw = "si_#{SecureRandom.hex(24)}"
    [ create!(agent: agent, name: name, scope: scope, token_digest: digest(raw)), raw ]
  end

  def self.authenticate(raw)
    token = find_by(token_digest: digest(raw.to_s))
    token&.update_column(:last_used_at, Time.current)
    token
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)

  def write? = scope == "write"
end
