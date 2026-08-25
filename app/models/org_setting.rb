class OrgSetting < ApplicationRecord
  encrypts :ms_client_secret, :google_client_secret
  has_one_attached :logo

  def self.current = first || create!

  def logo_url
    return nil unless logo.attached?
    Rails.application.routes.url_helpers.rails_storage_proxy_path(logo, only_path: true)
  end
end
