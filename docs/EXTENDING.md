# Extending Shared Inbox

Bolt-ons are ordinary code. There are three tiers, from loosest to tightest
coupling. Nothing needs a PR to core, a license key, or a marketplace.

## 1. Webhooks + REST API (any language, out of process)

Register a webhook (Settings → Webhooks or `POST /api/webhooks`) and you get a
signed JSON POST on: `thread.created`, `message.inbound`, `message.outbound`,
`thread.assigned`, `thread.status`. Verify `X-Inbox-Signature`
(`sha256=` + HMAC-SHA256 of the raw body with your webhook secret).

Everything the UI can do, the API can do — authenticate with
`Authorization: Bearer <token>` (Settings → API tokens).

### Hello world: auto-note on every inbound mail

```python
# pip install flask requests
from flask import Flask, request
import requests

app = Flask(__name__)
API = "https://inbox.example.com/api"
TOKEN = "si_..."  # write-scope token

@app.post("/hook")
def hook():
    event = request.json
    if event["event"] == "message.inbound":
        conv = event["data"]["conversation_id"]
        requests.post(f"{API}/conversations/{conv}/messages",
            headers={"Authorization": f"Bearer {TOKEN}"},
            json={"kind": "note", "body_text": "Seen by the bot 🤖"})
    return "", 204
```

## 2. MCP (bring your own model)

The MCP endpoint at `POST /mcp` (streamable HTTP, same Bearer token) exposes
`search`, `get_thread`, `draft_reply`, `send`, `list_mailboxes`, `assign`.
Point any MCP client at it; the client brings the LLM — core never calls one.

## 3. In-process plugins (Ruby, full access)

Drop a directory in `plugins/` with a `plugin.rb`; it loads at boot with full
access to models, services, and jobs. The two stable hook points:

```ruby
# plugins/auto_tagger/plugin.rb

# React to domain events (same events as webhooks, in process):
DomainEvents.subscribe("thread.created") do |payload|
  conversation = Conversation.find(payload[:id])
  if conversation.subject.match?(/invoice|billing/i)
    conversation.tags << Tag.find_or_create_by!(name: "billing")
  end
end

# Add an MCP tool:
class StatsTool < MCP::Tool
  tool_name "stats"
  description "Conversation counts by status"
  input_schema(properties: {}, required: [])
  def self.call(server_context:)
    MCP::Tool::Response.new([ { type: "text",
      text: Conversation.group(:status).count.to_json } ])
  end
end
McpTools.register(StatsTool)
```

`plugins/` is gitignored, so plugins survive upgrades; distribute one as a git
repo people clone into the directory. Anything more (routes, models,
migrations) can be a standard Rails engine gem — that is deliberately just
Rails, not a plugin framework of ours.

Model classes, service objects, and the event list are the public surface;
keep plugins small and they will keep working.
