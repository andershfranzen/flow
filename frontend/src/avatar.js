// Deterministic colored initial avatars.
const COLORS = ['#5522fa', '#e5484d', '#1a7f37', '#9a6700', '#0b74de', '#b0348d', '#5e6b1f', '#7048e8']

export function avatarColor(key) {
  let h = 0
  for (const c of String(key)) h = (h * 31 + c.charCodeAt(0)) >>> 0
  return COLORS[h % COLORS.length]
}

export function initials(nameOrEmail) {
  const s = String(nameOrEmail || '?').trim()
  const words = s.includes('@') ? [s] : s.split(/\s+/)
  if (words.length >= 2) return (words[0][0] + words[words.length - 1][0]).toUpperCase()
  return s.slice(0, 2).toUpperCase()
}
