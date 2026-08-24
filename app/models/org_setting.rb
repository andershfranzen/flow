class OrgSetting < ApplicationRecord
  encrypts :ms_client_secret, :google_client_secret

  def self.current = first || create!
end
