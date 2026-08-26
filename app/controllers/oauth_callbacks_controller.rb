# Browser lands here from the provider; state carries the mailbox.
class OauthCallbacksController < ActionController::Base
  def show
    target_origin = nil
    base = OrgSetting.current.canonical_base_url
    return render_result("OAuth is not configured", target_origin:, ok: false) unless base

    target_origin = URI(base).origin
    if params[:error].present?
      return render_result("Connection refused: #{params[:error_description] || params[:error]}",
                           target_origin:, ok: false)
    end
    state = MailOauth.verify_state!(params.require(:state))
    mailbox = Mailbox.find(state[:mailbox_id])
    MailOauth.connect!(mailbox, state[:provider], params.require(:code), "#{base.chomp('/')}/oauth/callback")
    render_result("#{mailbox.address} connected via #{state[:provider].capitalize}. You can close this window.",
                  target_origin:, ok: true)
  rescue MailOauth::Error, ActiveRecord::RecordNotFound, ActionController::ParameterMissing => e
    render_result("Connection failed: #{e.message}", target_origin:, ok: false)
  end

  private

  def render_result(message, target_origin:, ok:)
    script = if target_origin
      target_origin_json = ERB::Util.json_escape(target_origin.to_json)
      "<script>if (window.opener) { window.opener.postMessage({ flowOauth: #{ok} }, #{target_origin_json}); setTimeout(() => window.close(), 1500) }</script>"
    end
    html = <<~HTML
      <!doctype html><meta charset="utf-8"><title>Flow</title>
      <body style="font-family: system-ui; display: grid; place-items: center; height: 90vh">
      <div style="text-align: center"><h2>#{ok ? "✓" : "✗"}</h2><p>#{ERB::Util.html_escape(message)}</p></div>
      #{script}
    HTML
    render html: html.html_safe, status: ok ? :ok : :unprocessable_entity
  end
end
