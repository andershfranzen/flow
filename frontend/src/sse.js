// SSE client with reconnect + backoff (H20).
export function openStream(conversationId, handlers) {
  let source = null
  let closed = false
  let backoff = 1000

  function connect() {
    if (closed) return
    const url = conversationId ? `/api/stream?conversation_id=${conversationId}` : '/api/stream'
    source = new EventSource(url)
    source.addEventListener('hello', () => { backoff = 1000 })
    source.addEventListener('conversations', (e) => handlers.onConversations?.(JSON.parse(e.data)))
    source.addEventListener('presence', (e) => handlers.onPresence?.(JSON.parse(e.data)))
    source.onerror = () => {
      source.close()
      if (!closed) setTimeout(connect, backoff = Math.min(backoff * 2, 30000))
    }
  }
  connect()
  return { close() { closed = true; source?.close() } }
}
