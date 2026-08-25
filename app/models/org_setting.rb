class OrgSetting < ApplicationRecord
  encrypts :ms_client_secret, :google_client_secret
  has_one_attached :logo

  # CSS tokens an admin may re-color (Settings -> Appearance).
  THEME_KEYS = %w[accent accent_ink accent_soft highlight danger warn ok].freeze

  validates :crm_url, format: { with: %r{\Ahttps://[a-z0-9-]+\.crm\d{0,2}\.dynamics\.(com|de|us|cn)\z}i,
                                message: "must look like https://yourorg.crm4.dynamics.com" },
                      allow_blank: true

  def self.current = first || create!

  def logo_url
    return nil unless logo.attached?
    Rails.application.routes.url_helpers.rails_storage_proxy_path(logo, only_path: true)
  end
end
