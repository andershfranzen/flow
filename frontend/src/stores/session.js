import { defineStore } from 'pinia'
import { api, setCsrf } from '../api'
import { setLocale } from '../strings'

export const useSession = defineStore('session', {
  state: () => ({ agent: null, loaded: false }),
  getters: {
    isAdmin: (s) => s.agent?.role === 'admin',
  },
  actions: {
    async load() {
      const data = await api.get('/api/session')
      setCsrf(data.csrf_token)
      this.agent = data.agent
      this.loaded = true
    },
    async login(email, password) {
      const data = await api.post('/api/session', { email, password })
      setCsrf(data.csrf_token)
      this.agent = data.agent
      if (data.agent?.locale) setLocale(data.agent.locale)
    },
    async logout() {
      await api.delete('/api/session')
      this.agent = null
    },
  },
})
