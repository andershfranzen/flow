class OrgSetting < ApplicationRecord
  def self.current = first || create!
end
