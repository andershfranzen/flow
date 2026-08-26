require "rqrcode"

# TOTP two-factor for agents (I8). Secret is provisioned pending and only
# armed after the agent proves a valid code.
class Api::TwoFactorController < Api::BaseController
  PENDING_KEY = :pending_otp
  PENDING_TTL = 10.minutes

  def setup
    if current_agent.otp_required?
      return render json: { error: "otp_already_enabled" }, status: :unprocessable_entity
    end

    secret = Totp.generate_secret
    session[PENDING_KEY] = { "secret" => secret, "expires_at" => PENDING_TTL.from_now.to_i }
    uri = Totp.provisioning_uri(secret, account: current_agent.email)
    render json: { secret: secret, uri: uri,
                   qr_svg: RQRCode::QRCode.new(uri).as_svg(module_size: 4, viewbox: true) }
  end

  def enable
    if current_agent.otp_required?
      return render json: { error: "otp_already_enabled" }, status: :unprocessable_entity
    end

    pending = pending_otp
    unless pending && Totp.valid?(pending[:secret], params[:code])
      return render json: { error: "invalid_code" }, status: :unprocessable_entity
    end

    current_agent.update!(otp_secret: pending[:secret], otp_required: true)
    clear_pending_otp
    render json: { otp_required: true }
  end

  def disable
    if current_agent.otp_required?
      unless current_agent.otp_secret.present? && Totp.valid?(current_agent.otp_secret, params[:code])
        return render json: { error: "invalid_code" }, status: :unprocessable_entity
      end
      current_agent.update!(otp_required: false, otp_secret: nil)
    elsif current_agent.otp_secret.present?
      # Clear legacy unarmed secrets from versions that stored setup state on
      # the agent record rather than in the encrypted session.
      current_agent.update!(otp_secret: nil)
    end
    clear_pending_otp
    render json: { otp_required: false }
  end

  private

  def pending_otp
    pending = session[PENDING_KEY] || session[PENDING_KEY.to_s]
    return unless pending.is_a?(Hash)

    secret = pending["secret"] || pending[:secret]
    expires_at = (pending["expires_at"] || pending[:expires_at]).to_i
    if secret.blank? || expires_at <= Time.current.to_i
      clear_pending_otp
      return
    end
    { secret: secret, expires_at: expires_at }
  end

  def clear_pending_otp
    session.delete(PENDING_KEY)
    session.delete(PENDING_KEY.to_s)
  end
end
