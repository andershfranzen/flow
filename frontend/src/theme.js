// Org brand theming: admins re-color the accent tokens (Settings → Appearance);
// applyTheme() maps the stored overrides onto the CSS custom properties.
export const THEME_TOKENS = [
  { key: 'accent', cssVar: '--accent', default: '#5522fa', label: 'Accent', hint: 'Buttons, links, the Flow dot' },
  { key: 'accent_ink', cssVar: '--accent-ink', default: '#ffffff', label: 'Accent text', hint: 'Text on accent-colored buttons' },
  { key: 'accent_soft', cssVar: '--accent-soft', default: '#ece5ff', label: 'Accent wash', hint: 'Focus rings, soft highlights, login gradient' },
  { key: 'highlight', cssVar: '--highlight', default: '#ffd43b', label: 'Highlight', hint: 'Stars and unread badges' },
  { key: 'danger', cssVar: '--danger', default: '#e5484d', label: 'Danger', hint: 'Destructive actions and errors' },
  { key: 'warn', cssVar: '--warn', default: '#9a6700', label: 'Warning', hint: 'Cautions and pending states' },
  { key: 'ok', cssVar: '--ok', default: '#1a7f37', label: 'Success', hint: 'Confirmations and healthy states' },
]

const HEX = /^#[0-9a-fA-F]{6}$/

function darken(hex, amount = 0.14) {
  const n = parseInt(hex.slice(1), 16)
  const ch = (v) => Math.max(0, Math.round(v * (1 - amount)))
  return '#' + [ch(n >> 16), ch((n >> 8) & 255), ch(n & 255)]
    .map((v) => v.toString(16).padStart(2, '0')).join('')
}

export function applyTheme(theme) {
  const root = document.documentElement.style
  for (const t of THEME_TOKENS) {
    const value = HEX.test(theme?.[t.key] || '') ? theme[t.key] : null
    if (value && value !== t.default) root.setProperty(t.cssVar, value)
    else root.removeProperty(t.cssVar)
  }
  const accent = HEX.test(theme?.accent || '') ? theme.accent : null
  if (accent && accent !== '#5522fa') root.setProperty('--accent-hover', darken(accent))
  else root.removeProperty('--accent-hover')
}
