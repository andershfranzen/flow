import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { createRouter, createWebHistory } from 'vue-router'
import App from './App.vue'
import Login from './pages/Login.vue'
import Inbox from './pages/Inbox.vue'
import Settings from './pages/Settings.vue'
import { useSession } from './stores/session'
import { setLocale } from './strings'
import './style.css'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', component: Login },
    { path: '/', redirect: '/inbox' },
    { path: '/inbox', component: Inbox },
    { path: '/conversations/:id', component: Inbox, props: true },
    { path: '/settings/:tab?', component: Settings, props: true },
  ],
})

const app = createApp(App)
app.use(createPinia())
app.use(router)

const session = useSession()
router.beforeEach(async (to) => {
  if (!session.loaded) { try { await session.load() } catch { session.loaded = true } }
  if (session.agent?.locale) setLocale(session.agent.locale)
  document.body.classList.toggle('no-motion', session.agent?.ui_prefs?.motion === false)
  if (!session.agent && to.path !== '/login') return '/login'
  if (session.agent && to.path === '/login') return '/inbox'
})
window.addEventListener('api:unauthorized', () => {
  session.agent = null
  router.push('/login')
})

app.mount('#app')
