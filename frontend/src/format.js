function format(date, user, options) {
  const locale = user?.locale || undefined
  const timeZone = user?.timezone === 'auto' ? undefined : user?.timezone
  try {
    return new Intl.DateTimeFormat(locale, { ...options, timeZone }).format(date)
  } catch {
    return new Intl.DateTimeFormat(undefined, options).format(date)
  }
}

function hour12(user) {
  return user?.ui_prefs?.hour_cycle === '12'
}

// Short, context-aware timestamps: 14:32 today, 24 Aug otherwise.
export function shortTime(iso, user, now = new Date()) {
  if (!iso) return ''
  const d = new Date(iso)
  const day = { day: '2-digit', month: '2-digit', year: 'numeric' }
  if (format(d, user, day) === format(now, user, day))
    return format(d, user, { hour: '2-digit', minute: '2-digit', hour12: hour12(user) })
  if (format(d, user, { year: 'numeric' }) === format(now, user, { year: 'numeric' }))
    return format(d, user, { day: 'numeric', month: 'short' })
  return format(d, user, { day: 'numeric', month: 'short', year: 'numeric' })
}

export function fullTime(iso, user) {
  return iso ? format(new Date(iso), user, {
    day: 'numeric', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: hour12(user),
  }) : ''
}

export function dateOnly(iso, user) {
  return iso ? format(new Date(iso), user, { day: 'numeric', month: 'short', year: 'numeric' }) : ''
}

export function formatBytes(n) {
  if (n == null) return ''
  if (n < 1024) return `${n} B`
  if (n < 1048576) return `${(n / 1024).toFixed(n < 10240 ? 1 : 0)} KB`
  return `${(n / 1048576).toFixed(1)} MB`
}
