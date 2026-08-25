class PluginState < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  def self.enabled?(name)
    where(name: name).pick(:enabled) != false
  end

  def self.disabled_names
    where(enabled: false).pluck(:name)
  end
end
