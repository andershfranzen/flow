require "rqrcode"

# TOTP two-factor for agents (I8). Secret is provisioned pending and only
# armed after the agent proves a valid code.
class Api::TwoFactorController < Api::BaseController
  def setup
    current_agent.update!(otp_secret: Totp.generate_secret, otp_required: false)
    uri = Totp.provisioning_uri(current_agent.otp_secret, account: current_agent.email)
    render json: { secret: current_agent.otp_secret, uri: uri,
                   qr_svg: RQRCode::QRCode.new(uri).as_svg(module_size: 4, viewbox: true) }
  end

  def enable
    unless current_agent.otp_secret.present? && Totp.valid?(current_agent.otp_secret, params[:code])
      return render json: { error: "invalid_code" }, status: :unprocessable_entity
    end
    current_agent.update!(otp_required: true)
    render json: { otp_required: true }
  end

  def disable
    unless current_agent.otp_required? && Totp.valid?(current_agent.otp_secret, params[:code])
      return render json: { error: "invalid_code" }, status: :unprocessable_entity
    end
    current_agent.update!(otp_required: false, otp_secret: nil)
    render json: { otp_required: false }
  end
end
