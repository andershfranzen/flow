# Browser lands here from the provider; state carries the mailbox.
class OauthCallbacksController < ActionController::Base
  def show
    if params[:error].present?
      return render_result("Connection refused: #{params[:error_description] || params[:error]}", ok: false)
    end
    state = MailOauth.verify_state!(params.require(:state))
    mailbox = Mailbox.find(state[:mailbox_id])
    base = OrgSetting.current.base_url.presence || request.base_url
    MailOauth.connect!(mailbox, state[:provider], params.require(:code), "#{base.chomp('/')}/oauth/callback")
    render_result("#{mailbox.address} connected via #{state[:provider].capitalize}. You can close this window.", ok: true)
  rescue MailOauth::Error, ActiveRecord::RecordNotFound, ActionController::ParameterMissing => e
    render_result("Connection failed: #{e.message}", ok: false)
  end

  private

  def render_result(message, ok:)
    html = <<~HTML
      <!doctype html><meta charset="utf-8"><title>Flow</title>
      <body style="font-family: system-ui; display: grid; place-items: center; height: 90vh">
      <div style="text-align: center"><h2>#{ok ? "✓" : "✗"}</h2><p>#{ERB::Util.html_escape(message)}</p></div>
      <script>if (window.opener) { window.opener.postMessage({ flowOauth: #{ok} }, "*"); setTimeout(() => window.close(), 1500) }</script>
    HTML
    render html: html.html_safe, status: ok ? :ok : :unprocessable_entity
  end
end
