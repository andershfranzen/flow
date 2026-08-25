class PluginState < ApplicationRecord
  # Plugin config from Settings -> Plugins; may hold API keys, so encrypted.
  encrypts :settings

  validates :name, presence: true, uniqueness: true

  # NB: must load the record — pluck/pick skip attribute decryption.
  def self.settings_for(name)
    find_by(name: name)&.settings_hash || {}
  rescue ActiveRecord::Encryption::Errors::Decryption
    {}
  end

  def settings_hash
    settings.present? ? JSON.parse(settings) : {}
  rescue JSON::ParserError
    {}
  end

  def self.enabled?(name)
    where(name: name).pick(:enabled) != false
  end

  def self.disabled_names
    where(enabled: false).pluck(:name)
  end
end
