// Short, context-aware timestamps: 14:32 today, 24 Aug otherwise.
export function shortTime(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  const now = new Date()
  if (d.toDateString() === now.toDateString())
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  if (d.getFullYear() === now.getFullYear())
    return d.toLocaleDateString([], { day: 'numeric', month: 'short' })
  return d.toLocaleDateString([], { day: 'numeric', month: 'short', year: 'numeric' })
}

export function fullTime(iso) {
  return iso ? new Date(iso).toLocaleString() : ''
}
