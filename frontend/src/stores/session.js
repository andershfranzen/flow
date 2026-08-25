import { defineStore } from 'pinia'
import { api, setCsrf } from '../api'
import { setLocale } from '../strings'
import { applyTheme } from '../theme'

export const useSession = defineStore('session', {
  state: () => ({ agent: null, org: null, sso: null, loaded: false }),
  getters: {
    isAdmin: (s) => s.agent?.role === 'admin',
  },
  actions: {
    async load() {
      const data = await api.get('/api/session')
      setCsrf(data.csrf_token)
      this.agent = data.agent
      this.org = data.org || null
      this.sso = data.sso || null
      applyTheme(this.org?.theme)
      this.loaded = true
    },
    async login(email, password, otpCode) {
      const data = await api.post('/api/session', { email, password, otp_code: otpCode })
      setCsrf(data.csrf_token)
      this.agent = data.agent
      this.org = data.org || null
      applyTheme(this.org?.theme)
      if (data.agent?.locale) setLocale(data.agent.locale)
    },
    async logout() {
      await api.delete('/api/session')
      this.agent = null
    },
  },
})
