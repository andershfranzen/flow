# Streamable HTTP MCP endpoint (G5): POST /mcp with Bearer token auth.
class McpController < ApplicationController
  skip_forgery_protection

  def handle
    unless current_agent
      return render json: { jsonrpc: "2.0", error: { code: -32000, message: "unauthorized" }, id: nil },
                    status: :unauthorized
    end
    server = MCP::Server.new(
      name: OrgSetting.current.site_name,
      version: "1.0.0",
      tools: McpTools.all,
      server_context: { agent: current_agent, api_token: current_api_token }
    )
    render json: server.handle_json(request.body.read)
  end
end
