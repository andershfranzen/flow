class Customer < ApplicationRecord
  has_many :conversations, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  before_validation { self.email = email.to_s.downcase.strip }

  def self.for_email(email, name: nil)
    email = email.to_s.downcase.strip
    # Merged customers keep their old addresses in emails[] — match those too.
    customer = find_by(email: email) ||
               where("CAST(emails AS TEXT) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like("\"#{email}\"")}%").first ||
               create!(email: email)
    customer.update!(name: name) if name.present? && customer.name.blank?
    customer
  end

  def display_name = name.presence || email
end
