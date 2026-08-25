// SSE client with reconnect + backoff (H20).
export function openStream(conversationId, handlers) {
  let source = null
  let closed = false
  let backoff = 1000
  let stamp = null

  function connect() {
    if (closed) return
    const params = new URLSearchParams()
    if (conversationId) params.set('conversation_id', conversationId)
    if (stamp) params.set('since', stamp)
    source = new EventSource(`/api/stream?${params}`)
    source.addEventListener('hello', () => { backoff = 1000 })
    source.addEventListener('stamp', (e) => { stamp = JSON.parse(e.data).stamp })
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
