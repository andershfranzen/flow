// Rails API client: cookie session + CSRF header (H19/C4).
let csrfToken = null

export function setCsrf(token) { csrfToken = token }

async function request(method, path, body, opts = {}) {
  const headers = {}
  if (csrfToken) headers['X-CSRF-Token'] = csrfToken
  let payload
  if (body instanceof FormData) {
    payload = body
  } else if (body !== undefined) {
    headers['Content-Type'] = 'application/json'
    payload = JSON.stringify(body)
  }
  const res = await fetch(path, { method, headers, body: payload, credentials: 'same-origin' })
  if (res.status === 401) {
    let details = null
    try { details = await res.json() } catch {}
    if (details?.error === 'otp_required') {
      const err = new ApiError(401, 'otp_required')
      err.otpRequired = true
      throw err
    }
    if (!opts.allowUnauthorized) window.dispatchEvent(new CustomEvent('api:unauthorized'))
    throw new ApiError(401, details?.error || 'unauthorized')
  }
  if (!res.ok) {
    let details = null
    try { details = await res.json() } catch {}
    throw new ApiError(res.status, details?.error || res.statusText, details?.details)
  }
  if (res.status === 204) return null
  return res.json()
}

export class ApiError extends Error {
  constructor(status, message, details) {
    super(message)
    this.status = status
    this.details = details
  }
}

export const api = {
  get: (path) => request('GET', path),
  post: (path, body) => request('POST', path, body),
  patch: (path, body) => request('PATCH', path, body),
  put: (path, body) => request('PUT', path, body),
  delete: (path) => request('DELETE', path),
}
