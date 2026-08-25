class AddOtpToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :otp_secret, :string
    add_column :agents, :otp_required, :boolean, null: false, default: false
  end
end
