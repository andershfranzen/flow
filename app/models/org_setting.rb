class OrgSetting < ApplicationRecord
  encrypts :ms_client_secret, :google_client_secret
  has_one_attached :logo

  # CSS tokens an admin may re-color (Settings -> Appearance).
  THEME_KEYS = %w[accent accent_ink accent_soft highlight danger warn ok].freeze

  validates :crm_url, format: { with: %r{\Ahttps://[a-z0-9-]+\.crm\d{0,2}\.dynamics\.(com|de|us|cn)\z}i,
                                message: "must look like https://yourorg.crm4.dynamics.com" },
                      allow_blank: true

  def self.current = first || create!

  # Only configured HTTPS URLs may be used as browser OAuth origins. Never
  # derive this from the request Host header.
  def canonical_base_url
    value = base_url.to_s.strip
    return if value.blank?

    uri = URI.parse(value)
    return unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.blank? &&
      uri.query.blank? && uri.fragment.blank?

    value.sub(%r{/+\z}, "")
  rescue URI::InvalidURIError
    nil
  end

  def logo_url
    return nil unless logo.attached?
    Rails.application.routes.url_helpers.rails_storage_proxy_path(logo, only_path: true)
  end
end
