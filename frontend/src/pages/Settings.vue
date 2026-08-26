<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useSession } from '../stores/session'
import { api } from '../api'
import { t, setLocale } from '../strings'
import WorkflowBuilder from '../components/WorkflowBuilder.vue'
import RichEditor from '../components/RichEditor.vue'
import ReportsPanel from '../components/ReportsPanel.vue'
import { ArrowLeft, ExternalLink } from 'lucide-vue-next'
import { THEME_TOKENS, applyTheme } from '../theme'
import ColorPicker from '../components/ColorPicker.vue'
import SaveButton from '../components/SaveButton.vue'
import TogglePills from '../components/TogglePills.vue'
import StyledSelect from '../components/StyledSelect.vue'

const props = defineProps({ tab: String })
const router = useRouter()
const session = useSession()

const GROUPS = computed(() => {
  const personal = {
    label: 'My settings',
    tabs: [['profile', 'My profile'], ['saved_replies', 'Saved replies'], ['tags', 'Tags'], ['tokens', 'API tokens']],
  }
  const admin = {
    label: 'Administration',
    tabs: [['org', 'Organisation'], ['appearance', 'Appearance'], ['agents', 'Agents'], ['teams', 'Teams'], ['mailboxes', 'Mailboxes'],
           ['workflows', 'Workflows'], ['reports', 'Reports'], ['webhooks', 'Webhooks'], ['plugins', 'Plugins']],
  }
  return session.isAdmin ? [personal, admin] : [personal]
})
const tab = computed(() => props.tab || 'profile')

const org = ref({})
const agents = ref([])
const mailboxes = ref([])
const savedReplies = ref([])
const tags = ref([])
const webhooks = ref([])
const tokens = ref([])
const editing = ref(null) // current edit object for the open tab
const flash = ref('')
const newToken = ref(null)
const testResult = ref(null)

const profile = ref({ name: '', current_password: '', password: '', notify_prefs: {}, ui_prefs: { motion: true }, muted_mailbox_ids: [] })
const teams = ref([])
const plugins = ref([])
const restartHint = ref('')
const installUrl = ref('')
const openSettingsFor = ref(null)
const pluginBusy = ref(false)
const zipInput = ref(null)
const otp = ref({ setup: null, code: '', enabled: false })
const TIMEZONES = Intl.supportedValuesOf('timeZone')

async function load() {
  flash.value = ''
  editing.value = null
  if (tab.value === 'org' && session.isAdmin) org.value = await api.get('/api/org_settings')
  if (tab.value === 'appearance' && session.isAdmin) {
    org.value = await api.get('/api/org_settings')
    theme.value = Object.fromEntries(THEME_TOKENS.map((tk) => [tk.key, (org.value.theme || {})[tk.key] || tk.default]))
  } else if (session.org) {
    applyTheme(session.org.theme) // drop any unsaved preview when leaving Appearance
  }
  if (tab.value === 'agents' && session.isAdmin) {
    agents.value = await api.get('/api/agents')
    mailboxes.value = await api.get('/api/mailboxes')
  }
  if (tab.value === 'mailboxes' && session.isAdmin) mailboxes.value = await api.get('/api/mailboxes')
  if (tab.value === 'teams' && session.isAdmin) {
    teams.value = await api.get('/api/teams')
    agents.value = await api.get('/api/agents')
  }
  if (tab.value === 'saved_replies') {
    savedReplies.value = await api.get('/api/saved_replies')
    mailboxes.value = await api.get('/api/mailboxes')
  }
  if (tab.value === 'tags') tags.value = await api.get('/api/tags')
  if (tab.value === 'webhooks' && session.isAdmin) webhooks.value = await api.get('/api/webhooks')
  if (tab.value === 'plugins' && session.isAdmin) {
    const data = await api.get('/api/plugins')
    plugins.value = data.plugins
    restartHint.value = data.restart_hint
  }
  if (tab.value === 'tokens') {
    tokens.value = await api.get('/api/api_tokens')
    const me = await api.get('/api/me')
    otp.value = { setup: null, code: '', enabled: !!me.otp_required }
  }
  if (tab.value === 'profile') {
    const me = await api.get('/api/me')
    otp.value = { setup: null, code: '', enabled: !!me.otp_required }
    mailboxes.value = await api.get('/api/mailboxes')
    profile.value = { name: me.name, current_password: '', password: '', otp_code: '', locale: me.locale, timezone: me.timezone,
                      signature: me.signature || '',
                      notify_prefs: me.notify_prefs, ui_prefs: { motion: true, ...(me.ui_prefs || {}) },
                      muted_mailbox_ids: me.muted_mailbox_ids || [] }
  }
}
onMounted(load)
watch(tab, load)

const justSaved = ref(false)
function ok(msg = 'Saved') {
  if (msg === 'Saved') {
    justSaved.value = true
    setTimeout(() => (justSaved.value = false), 1600)
    return
  }
  flash.value = msg
  setTimeout(() => (flash.value = ''), 2500)
}

// Appearance: live-preview while picking, persist on save (H-theme)
const theme = ref({})
const openPicker = ref(null)
function setToken(tk, raw, el) {
  let v = raw.trim().toLowerCase()
  if (/^[0-9a-f]{6}$/.test(v)) v = '#' + v
  if (!/^#[0-9a-f]{6}$/.test(v)) { if (el) el.value = theme.value[tk.key]; return }
  theme.value[tk.key] = v
  applyTheme(theme.value)
}
function resetToken(tk) { theme.value[tk.key] = tk.default; applyTheme(theme.value) }
function resetAllTheme() { THEME_TOKENS.forEach((tk) => (theme.value[tk.key] = tk.default)); applyTheme(theme.value) }
async function saveTheme() {
  org.value = await api.patch('/api/org_settings', { theme: theme.value })
  if (session.org) session.org.theme = org.value.theme
  applyTheme(org.value.theme)
  ok()
}

async function saveOrg() { org.value = await api.patch('/api/org_settings', org.value); ok() }
const logoError = ref('')
const logoInput = ref(null)
async function patchLogo(fd) {
  logoError.value = ''
  try {
    org.value = await api.patch('/api/org_settings', fd)
    if (session.org) session.org.logo_url = org.value.logo_url // rail updates live
    ok()
  } catch (e) { logoError.value = e.details?.[0] || e.message }
}
function uploadLogo(e) {
  const file = e.target.files?.[0]
  if (!file) return
  const fd = new FormData()
  fd.append('logo', file)
  patchLogo(fd)
  e.target.value = ''
}
function removeLogo() {
  const fd = new FormData()
  fd.append('remove_logo', '1')
  patchLogo(fd)
}

async function saveProfile() {
  try {
    await api.patch('/api/me', profile.value)
  } catch (e) {
    flash.value = e.message === 'otp_required' ? 'Authenticator code required' : (e.details?.[0] || e.message)
    return
  }
  profile.value.current_password = ''
  profile.value.password = ''
  profile.value.otp_code = ''
  setLocale(profile.value.locale)
  if (session.agent) session.agent.locale = profile.value.locale
  document.body.classList.toggle('no-motion', profile.value.ui_prefs.motion === false)
  ok()
}

async function otpSetup() {
  try {
    otp.value.setup = await api.post('/api/me/2fa/setup')
  } catch (e) {
    flash.value = e.details?.[0] || e.message
  }
}
async function otpEnable() {
  try {
    await api.post('/api/me/2fa/enable', { code: otp.value.code })
    otp.value = { setup: null, code: '', enabled: true }
    ok('Two-factor enabled')
  } catch { flash.value = 'Wrong code — try again' }
}
async function otpDisable() {
  const code = window.prompt('Enter a current code from your authenticator to disable 2FA:')
  if (!code) return
  try {
    await api.post('/api/me/2fa/disable', { code })
    otp.value = { setup: null, code: '', enabled: false }
    ok('Two-factor disabled')
  } catch { flash.value = 'Wrong code' }
}

async function saveTeam() {
  const x = editing.value
  if (x.id) await api.patch(`/api/teams/${x.id}`, x)
  else await api.post('/api/teams', x)
  await load(); ok()
}

// Agents
function mailboxNames(a) {
  const names = mailboxes.value.filter((m) => a.mailbox_ids.includes(m.id)).map((m) => m.name)
  if (!names.length) return 'No access'
  return names.length > 3 ? `${names.slice(0, 3).join(', ')} +${names.length - 3}` : names.join(', ')
}
function newAgent() { editing.value = { role: 'user', mailbox_ids: [], password: '' } }
async function saveAgent() {
  const a = editing.value
  if (a.id) await api.patch(`/api/agents/${a.id}`, a)
  else await api.post('/api/agents', a)
  await load(); ok()
}
async function deleteAgent(a) {
  if (!confirm(`Delete agent ${a.name}?`)) return
  await api.delete(`/api/agents/${a.id}`); await load()
}

// Mailboxes
function newMailbox() {
  editing.value = { auth_kind: 'password', imap_port: 993, imap_ssl: true, imap_folder: 'INBOX', smtp_port: 587, smtp_security: 'starttls' }
}

async function connectOauth() {
  await saveMailbox()
  try {
    const { url } = await api.post(`/api/oauth/${editing.value.auth_kind}/start`, { mailbox_id: editing.value.id })
    const popup = window.open(url, 'flow-oauth', 'width=560,height=680')
    const onMessage = async (e) => {
      if (e.data?.flowOauth === undefined) return
      window.removeEventListener('message', onMessage)
      popup?.close()
      editing.value = await api.get(`/api/mailboxes/${editing.value.id}`)
      ok(e.data.flowOauth ? 'Connected' : 'Connection failed')
    }
    window.addEventListener('message', onMessage)
  } catch (err) {
    flash.value = err.details?.[0] || 'OAuth app not configured — see Organisation settings'
  }
}
async function editMailbox(m) { editing.value = await api.get(`/api/mailboxes/${m.id}`); testResult.value = null }
async function saveMailbox() {
  const m = editing.value
  const saved = m.id ? await api.patch(`/api/mailboxes/${m.id}`, m) : await api.post('/api/mailboxes', m)
  editing.value = { ...editing.value, id: saved.id }
  await load(); editing.value = await api.get(`/api/mailboxes/${saved.id}`); ok()
}
async function testMailbox() {
  await saveMailbox()
  testResult.value = await api.post(`/api/mailboxes/${editing.value.id}/test`)
}
async function deleteMailbox(m) {
  if (!confirm(`Delete mailbox ${m.address} and all its conversations?`)) return
  await api.delete(`/api/mailboxes/${m.id}`); await load()
}

// Saved replies / tags / webhooks / tokens
async function saveSavedReply() {
  const r = editing.value
  if (r.id) await api.patch(`/api/saved_replies/${r.id}`, r)
  else await api.post('/api/saved_replies', r)
  await load(); ok()
}
async function saveTag() {
  const x = editing.value
  if (x.id) await api.patch(`/api/tags/${x.id}`, x)
  else await api.post('/api/tags', x)
  await load(); ok()
}
async function saveWebhook() {
  const w = editing.value
  if (w.id) {
    await api.patch(`/api/webhooks/${w.id}`, w)
    await load(); ok()
  } else {
    const saved = await api.post('/api/webhooks', w)
    await load()
    editing.value = saved
    ok('Webhook created — copy the signing secret now')
  }
}
async function createToken() {
  try {
    newToken.value = await api.post('/api/api_tokens', editing.value)
    editing.value = null
    await load()
  } catch (e) {
    flash.value = e.message === 'otp_required' ? 'Authenticator code required' : (e.details?.[0] || e.message)
  }
}
async function del(path) { await api.delete(path); await load() }

async function togglePlugin(p) {
  const data = await api.patch(`/api/plugins/${p.name}`, { enabled: !p.enabled })
  plugins.value = data.plugins
}

const pluginSettingsForm = ref({})
function toggleSettingsFor(p) {
  if (openSettingsFor.value === p.name) { openSettingsFor.value = null; return }
  openSettingsFor.value = p.name
  pluginSettingsForm.value = Object.fromEntries(
    (p.settings_spec || []).map((f) => [f.key, f.type === 'password' ? '' : (p.settings?.[f.key] ?? '')]))
}
async function savePluginSettings(p) {
  const data = await api.patch(`/api/plugins/${p.name}`, { settings: pluginSettingsForm.value })
  plugins.value = data.plugins
  const fresh = data.plugins.find((x) => x.name === p.name)
  pluginSettingsForm.value = Object.fromEntries(
    (fresh?.settings_spec || []).map((f) => [f.key, f.type === 'password' ? '' : (fresh.settings?.[f.key] ?? '')]))
  ok()
}

async function installZip(e) {
  const file = e.target.files?.[0]
  e.target.value = ''
  if (!file) return
  pluginBusy.value = true
  try {
    const fd = new FormData()
    fd.append('file', file)
    const data = await api.post('/api/plugins/install_zip', fd)
    plugins.value = data.plugins
    ok('Installed')
  } catch (err) {
    flash.value = err.details?.[0] || `Install failed: ${err.message}`
  } finally {
    pluginBusy.value = false
  }
}

async function installPlugin() {
  pluginBusy.value = true
  try {
    const data = await api.post('/api/plugins/install', { git_url: installUrl.value.trim() })
    plugins.value = data.plugins
    installUrl.value = ''
    ok('Installed')
  } catch (e) {
    flash.value = e.details?.[0] || `Install failed: ${e.message}`
  } finally {
    pluginBusy.value = false
  }
}

async function upgradePlugin(p) {
  const data = await api.post(`/api/plugins/${p.name}/upgrade`)
  ok(data.ok ? `Updated: ${data.output} — restart to apply` : `Update failed: ${data.output}`)
}

async function removePlugin(p) {
  if (!confirm(`Uninstall plugin "${p.name}"? Its files are deleted.`)) return
  const data = await api.delete(`/api/plugins/${p.name}`)
  plugins.value = data.plugins
}

const WEBHOOK_EVENTS = [
  { id: 'thread.created', label: 'thread.created', sub: 'New conversation opened' },
  { id: 'message.inbound', label: 'message.inbound', sub: 'Customer message received' },
  { id: 'message.outbound', label: 'message.outbound', sub: 'Agent reply sent' },
  { id: 'thread.assigned', label: 'thread.assigned', sub: 'Conversation assigned' },
  { id: 'thread.status', label: 'thread.status', sub: 'Status changed' },
]
const NOTIFY_LABELS = {
  new_unassigned: 'New unassigned conversation',
  assigned_to_me: 'Conversation assigned to me',
  customer_reply: 'Customer replies on mine',
  note_on_mine: 'Note added on mine',
}
</script>

<template>
  <main class="settings-wrap">
    <p><router-link to="/inbox" style="display:inline-flex; align-items:center; gap:5px"><ArrowLeft :size="14" /> Inbox</router-link></p>
    <h1>{{ t.settings }}</h1>
    <nav class="settings-nav">
      <div v-for="group in GROUPS" :key="group.label" class="settings-group">
        <div class="settings-group-label">{{ group.label }}</div>
        <div class="settings-tabs">
          <button v-for="[key, label] in group.tabs" :key="key" :class="{ active: tab === key }"
                  @click="router.push(`/settings/${key}`)">{{ label }}</button>
        </div>
      </div>
    </nav>
    <p v-if="flash" class="ok-text">{{ flash }}</p>

    <!-- Appearance -->
    <div v-if="tab === 'appearance'" class="card">
      <h3>Brand colors</h3>
      <p class="hint-text">These tokens color the whole app for everyone. Click a swatch to pick from the
        gradient, or type a hex code. Changes preview live on this screen and apply org-wide once saved.</p>
      <div class="theme-rows">
        <div v-for="tk in THEME_TOKENS" :key="tk.key" class="theme-row">
          <span class="swatch-wrap">
            <button type="button" class="swatch" :style="{ background: theme[tk.key] }"
                    :aria-label="'Pick ' + tk.label.toLowerCase()" :aria-expanded="openPicker === tk.key"
                    @click="openPicker = openPicker === tk.key ? null : tk.key" />
            <ColorPicker v-if="openPicker === tk.key" :model-value="theme[tk.key]"
                         @update:model-value="(v) => setToken(tk, v)" @close="openPicker = null" />
          </span>
          <div class="theme-meta">
            <div class="theme-label">{{ tk.label }}</div>
            <div class="theme-hint">{{ tk.hint }}</div>
          </div>
          <input class="hex-input" :value="theme[tk.key]" spellcheck="false" aria-label="Hex code"
                 @change="setToken(tk, $event.target.value, $event.target)" />
          <button type="button" class="ghost" :style="{ visibility: theme[tk.key] !== tk.default ? 'visible' : 'hidden' }"
                  @click="resetToken(tk)">Reset</button>
        </div>
      </div>
      <div class="theme-actions">
        <SaveButton type="button" :saved="justSaved" @click="saveTheme" />
        <button type="button" class="ghost" @click="resetAllTheme">Reset all to Flow defaults</button>
      </div>
    </div>

    <!-- Org -->
    <form v-if="tab === 'org'" class="card" @submit.prevent="saveOrg">
      <div class="form-grid">
        <div><label>Site name</label><input v-model="org.site_name" style="width:100%" /></div>
        <div><label>Base URL</label><input v-model="org.base_url" placeholder="https://inbox.example.com" style="width:100%" /></div>
        <div><label>Notify from (email)</label><input v-model="org.notify_from" style="width:100%" /></div>
      </div>

      <h3 style="margin-top:16px">Company logo</h3>
      <p class="hint-text">Shown at the top of the sidebar for everyone, with a small "by Flow" underneath.
        PNG, JPEG or WebP up to 1&nbsp;MB — a wide, transparent logo works best.</p>
      <div class="logo-row">
        <img v-if="org.logo_url" :src="org.logo_url" class="logo-preview" alt="Company logo" />
        <input ref="logoInput" type="file" accept="image/png,image/jpeg,image/webp" @change="uploadLogo" hidden />
        <button type="button" @click="logoInput?.click()">{{ org.logo_url ? 'Replace logo…' : 'Upload logo…' }}</button>
        <button v-if="org.logo_url" type="button" class="ghost" @click="removeLogo">Remove</button>
      </div>
      <p v-if="logoError" class="error-text">{{ logoError }}</p>

      <h3 style="margin-top:16px">Company signature (all mailboxes)</h3>
      <p class="hint-text">Used when neither the agent nor the mailbox has its own signature.
        Leave every signature field empty if signatures are stamped centrally by your provider
        (Microsoft 365 transport rules, Exclaimer, CodeTwo …).</p>
      <div class="modal-editor"><RichEditor v-model="org.default_signature" placeholder="Best regards, the Support team" /></div>

      <h3 style="margin-top:16px">Microsoft 365 OAuth app</h3>
      <p class="hint-text">Register one app in Entra ID. User-delegated mailboxes need
        <code>IMAP.AccessAsUser.All</code> + <code>SMTP.Send</code> and redirect URI
        <code>{{ org.base_url || '&lt;base url&gt;' }}/oauth/callback</code>. App-only mailboxes need the
        Office 365 Exchange Online application permissions <code>IMAP.AccessAsApp</code> +
        <code>SMTP.SendAsApp</code>, tenant admin consent, and mailbox-scoped FullAccess + SendAs grants
        for the Exchange service principal.</p>
      <div class="form-grid">
        <div><label>Client ID</label><input v-model="org.ms_client_id" style="width:100%" /></div>
        <div><label>Client secret {{ org.ms_client_secret_set ? '(set — blank keeps it)' : '' }}</label>
          <input v-model="org.ms_client_secret" type="password" style="width:100%" /></div>
        <div><label>Tenant (or "common")</label><input v-model="org.ms_tenant" style="width:100%" /></div>
      </div>

      <h3 style="margin-top:16px">Sign in with Microsoft</h3>
      <p class="hint-text">When enabled, everyone signs in through the Entra app above and password login is
        turned off. New sign-ins can auto-create agent accounts, but only for the listed email domains.
        Auto-created agents start without mailbox access; an admin must grant it.
        Add a second redirect URI <code>{{ org.base_url || '&lt;base url&gt;' }}/auth/microsoft/callback</code>
        with the <code>openid email profile</code> scopes to the app registration.</p>
      <label class="choice"><input type="checkbox" v-model="org.ms_sso_enabled" />
        Enable Microsoft sign-in (disables password login)</label>
      <label class="choice"><input type="checkbox" v-model="org.sso_auto_provision" />
        Auto-create agents on first sign-in</label>
      <div class="form-grid">
        <div><label>Allowed sign-in domains (comma-separated)</label>
          <input v-model="org.sso_allowed_domains" placeholder="acmecool.com" style="width:100%" /></div>
      </div>
      <h3 style="margin-top:16px">Agent access (MCP)</h3>
      <p class="hint-text">Flow speaks the Model Context Protocol at
        <code>{{ (org.base_url || '&lt;base url&gt;') + '/mcp' }}</code>. Connect any MCP-capable AI agent using an
        API token (Settings → API tokens) as the Bearer token. A write-scope token from an admin account can
        configure this entire Flow — mailboxes, agents, teams, workflows, webhooks, branding — so an agent can do
        the full setup for you. Access always follows the token's scope and the agent's role.</p>
      <label class="choice"><input type="checkbox" v-model="org.mcp_enabled" /> Enable the MCP endpoint</label>

      <h3 style="margin-top:16px">Microsoft Dynamics 365 CRM</h3>
      <p class="hint-text">Shows the customer's CRM contact and company in the Insights sidebar.
        Uses the Entra app above with a client-credentials login, so the tenant must be your real tenant ID
        (not "common") and Dynamics needs an <em>application user</em> for the app with read access to
        contacts and accounts.</p>
      <label class="choice"><input type="checkbox" v-model="org.crm_enabled" /> Enable Dynamics 365 lookups</label>
      <div class="form-grid">
        <div><label>Dynamics org URL</label>
          <input v-model="org.crm_url" placeholder="https://yourorg.crm4.dynamics.com" style="width:100%" /></div>
      </div>

      <h3 style="margin-top:16px">Google OAuth app</h3>
      <p class="hint-text">Google Cloud OAuth client (web), scope <code>https://mail.google.com/</code>, same redirect URI.</p>
      <div class="form-grid">
        <div><label>Client ID</label><input v-model="org.google_client_id" style="width:100%" /></div>
        <div><label>Client secret {{ org.google_client_secret_set ? '(set — blank keeps it)' : '' }}</label>
          <input v-model="org.google_client_secret" type="password" style="width:100%" /></div>
      </div>
      <div class="form-actions"><SaveButton :saved="justSaved" :label="t.save" /></div>
    </form>

    <!-- Agents -->
    <div v-if="tab === 'agents'">
      <div class="form-actions" style="margin:0 0 12px"><button class="primary" @click="newAgent">Add agent</button></div>
      <table class="card" style="padding:0">
        <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Mailboxes</th><th></th></tr></thead>
        <tbody>
          <tr v-for="a in agents" :key="a.id">
            <td>{{ a.name }}</td><td>{{ a.email }}</td><td>{{ a.role }}</td>
            <td style="color:var(--muted)">{{ a.role === 'admin' ? 'All mailboxes' : mailboxNames(a) }}</td>
            <td style="text-align:right">
              <button class="ghost" @click="editing = { ...a, password: '' }">Edit</button>
              <button class="ghost" @click="deleteAgent(a)">{{ t.delete }}</button>
            </td>
          </tr>
        </tbody>
      </table>
      <form v-if="editing" class="card" @submit.prevent="saveAgent">
        <h3>{{ editing.id ? 'Edit agent' : 'New agent' }}</h3>
        <div class="form-grid">
          <div><label>Name</label><input v-model="editing.name" required style="width:100%" /></div>
          <div><label>Email</label><input v-model="editing.email" type="email" required style="width:100%" /></div>
          <div><label>Password {{ editing.id ? '(leave blank to keep)' : '' }}</label>
            <input v-model="editing.password" type="password" :required="!editing.id" style="width:100%" /></div>
          <div><label>Role</label>
            <StyledSelect v-model="editing.role" style="width:100%"
                          :options="[{ value: 'user', label: 'User' }, { value: 'admin', label: 'Admin' }]" /></div>
        </div>
        <div style="margin-top:12px">
          <label>Mailbox access</label>
          <p v-if="editing.role === 'admin'" class="hint-text" style="margin:0">
            Admins always see every mailbox.</p>
          <template v-else>
            <TogglePills v-model="editing.mailbox_ids"
                         :options="mailboxes.map((m) => ({ id: m.id, label: m.name, sub: m.address }))" />
            <p v-if="!editing.mailbox_ids.length" class="hint-text" style="margin:6px 0 0">
              No access yet — this agent will see an empty inbox until you grant a mailbox.</p>
          </template>
        </div>
        <div class="form-actions">
          <button class="primary">{{ t.save }}</button>
          <button type="button" @click="editing = null">{{ t.cancel }}</button>
        </div>
      </form>
    </div>

    <!-- Teams -->
    <div v-if="tab === 'teams'">
      <div class="form-actions" style="margin:0 0 12px">
        <button class="primary" @click="editing = { name: '', agent_ids: [] }">Add team</button>
        <span class="hint-text" style="margin:0">Teams round-robin conversations via the workflow action "Assign to team".</span>
      </div>
      <table class="card" style="padding:0">
        <tbody>
          <tr v-for="x in teams" :key="x.id">
            <td><strong>{{ x.name }}</strong></td>
            <td style="color:var(--muted)">{{ x.agent_ids.length }} member{{ x.agent_ids.length === 1 ? '' : 's' }}</td>
            <td style="text-align:right">
              <button class="ghost" @click="editing = { ...x }">Edit</button>
              <button class="ghost" @click="del(`/api/teams/${x.id}`)">{{ t.delete }}</button>
            </td>
          </tr>
        </tbody>
      </table>
      <form v-if="editing" class="card" @submit.prevent="saveTeam">
        <div><label>Team name</label><input v-model="editing.name" required style="width:100%" /></div>
        <div style="margin-top:10px">
          <label>Members (round-robin order follows agent id)</label>
          <TogglePills v-model="editing.agent_ids"
                       :options="agents.map((a) => ({ id: a.id, label: a.name, sub: a.email }))" />
        </div>
        <div class="form-actions">
          <button class="primary">{{ t.save }}</button>
          <button type="button" @click="editing = null">{{ t.cancel }}</button>
        </div>
      </form>
    </div>

    <!-- Mailboxes -->
    <div v-if="tab === 'mailboxes'">
      <div class="form-actions" style="margin:0 0 12px"><button class="primary" @click="newMailbox">Add mailbox</button></div>
      <table class="card" style="padding:0">
        <thead><tr><th>Name</th><th>Address</th><th>Last fetch</th><th>Status</th><th></th></tr></thead>
        <tbody>
          <tr v-for="m in mailboxes" :key="m.id">
            <td>{{ m.name }}</td><td>{{ m.address }}</td>
            <td>{{ m.last_fetched_at ? new Date(m.last_fetched_at).toLocaleString() : 'never' }}</td>
            <td><span v-if="m.fetch_error" class="pill bounce" :title="m.fetch_error">error</span><span v-else class="pill status-active">ok</span></td>
            <td style="text-align:right">
              <button class="ghost" @click="editMailbox(m)">Edit</button>
              <button class="ghost" @click="deleteMailbox(m)">{{ t.delete }}</button>
            </td>
          </tr>
        </tbody>
      </table>
      <form v-if="editing" class="card" @submit.prevent="saveMailbox">
        <h3>{{ editing.id ? editing.address : 'New mailbox' }}</h3>
        <div class="form-grid">
          <div><label>Name</label><input v-model="editing.name" required style="width:100%" /></div>
          <div><label>Address</label><input v-model="editing.address" type="email" required style="width:100%" /></div>
          <div><label>From name (optional)</label><input v-model="editing.from_name" style="width:100%" /></div>
        </div>
        <h3 style="margin-top:14px">Authentication</h3>
        <div class="form-grid">
          <div><label>Method</label>
            <StyledSelect v-model="editing.auth_kind" style="width:100%"
                          :options="[{ value: 'password', label: 'Password (IMAP/SMTP)' },
                                     { value: 'microsoft', label: 'Microsoft 365 (delegated OAuth)' },
                                     { value: 'microsoft_app', label: 'Microsoft 365 (app-only OAuth)' },
                                     { value: 'google', label: 'Google (OAuth)' }]" /></div>
          <div v-if="editing.auth_kind === 'microsoft' || editing.auth_kind === 'google'" style="align-self:end; display:flex; gap:8px; align-items:center">
            <button type="button" class="primary" @click="connectOauth">
              Connect {{ editing.auth_kind === 'microsoft' ? 'Microsoft 365' : 'Google' }}
            </button>
            <span v-if="editing.oauth_connected" class="pill status-active">connected</span>
            <span v-else class="pill">not connected</span>
          </div>
          <div v-else-if="editing.auth_kind === 'microsoft_app'" style="align-self:end">
            <span v-if="editing.oauth_connected" class="pill status-active">app configured</span>
            <span v-else class="pill">configure the Microsoft app above</span>
          </div>
        </div>
        <p v-if="editing.auth_kind === 'microsoft_app'" class="hint-text">No user signs in and no refresh token is stored.
          Flow requests short-lived client-credentials tokens and authenticates as this mailbox address.</p>
        <h3 style="margin-top:14px">IMAP (incoming)</h3>
        <div class="form-grid">
          <div><label>Host</label><input v-model="editing.imap_host" style="width:100%" /></div>
          <div><label>Port</label><input v-model.number="editing.imap_port" type="number" style="width:100%" /></div>
          <div><label>User</label><input v-model="editing.imap_user" style="width:100%" /></div>
          <div v-if="editing.auth_kind === 'password'"><label>Password {{ editing.imap_password_set ? '(set — blank keeps it)' : '' }}</label>
            <input v-model="editing.imap_password" type="password" style="width:100%" /></div>
          <div><label>Folder</label><input v-model="editing.imap_folder" style="width:100%" /></div>
          <div><label>Encryption</label>
            <label class="choice" style="padding:8px 0"><input type="checkbox" v-model="editing.imap_ssl" /> SSL</label></div>
        </div>
        <h3 style="margin-top:14px">SMTP (outgoing)</h3>
        <div class="form-grid">
          <div><label>Host</label><input v-model="editing.smtp_host" style="width:100%" /></div>
          <div><label>Port</label><input v-model.number="editing.smtp_port" type="number" style="width:100%" /></div>
          <div><label>User</label><input v-model="editing.smtp_user" style="width:100%" /></div>
          <div v-if="editing.auth_kind === 'password'"><label>Password {{ editing.smtp_password_set ? '(set — blank keeps it)' : '' }}</label>
            <input v-model="editing.smtp_password" type="password" style="width:100%" /></div>
          <div><label>Security</label>
            <StyledSelect v-model="editing.smtp_security" style="width:100%"
                          :options="[{ value: 'starttls', label: 'STARTTLS' }, { value: 'ssl', label: 'SSL/TLS' }, { value: 'none', label: 'None' }]" /></div>
        </div>
        <h3 style="margin-top:14px">Auto-reply</h3>
        <label class="choice"><input type="checkbox" v-model="editing.auto_reply_enabled" /> Send "we got your mail" once per new conversation</label>
        <textarea v-if="editing.auto_reply_enabled" v-model="editing.auto_reply_body" rows="3" style="width:100%"
                  placeholder="Thanks — we received your message and will reply soon."></textarea>
        <div style="margin-top:10px"><label>Signature (appended to replies — formatting and logos supported; leave empty if your provider stamps signatures)</label>
          <div class="modal-editor"><RichEditor v-model="editing.signature" placeholder="Best regards…" /></div></div>
        <div class="form-actions">
          <button class="primary">{{ t.save }}</button>
          <button type="button" @click="testMailbox">Test connection</button>
          <button type="button" @click="editing = null">{{ t.cancel }}</button>
          <span v-if="testResult">
            IMAP: <span :class="testResult.imap.ok ? 'ok-text' : 'error-text'">{{ testResult.imap.ok ? 'ok' : testResult.imap.error }}</span> ·
            SMTP: <span :class="testResult.smtp.ok ? 'ok-text' : 'error-text'">{{ testResult.smtp.ok ? 'ok' : testResult.smtp.error }}</span>
          </span>
        </div>
      </form>
    </div>

    <!-- Workflows -->
    <WorkflowBuilder v-if="tab === 'workflows'" />

    <!-- Reports -->
    <ReportsPanel v-if="tab === 'reports'" />

    <!-- Plugins -->
    <div v-if="tab === 'plugins'">
      <form class="card" @submit.prevent="installPlugin" style="display:flex; gap:8px; align-items:end; flex-wrap:wrap">
        <div style="flex:1; min-width:240px">
          <label>Install from git URL</label>
          <input v-model="installUrl" required placeholder="https://github.com/someone/flow-plugin-example.git" style="width:100%" />
        </div>
        <button class="primary" :disabled="pluginBusy">Install</button>
        <input ref="zipInput" type="file" accept=".zip,application/zip" hidden @change="installZip" />
        <button type="button" :disabled="pluginBusy" @click="zipInput?.click()"
                data-tip="Upload a plugin as a .zip — WordPress-style">Upload .zip…</button>
      </form>
      <p class="hint-text">{{ restartHint }} Plugins run with full access to Flow — install only code you trust.
        <a href="https://github.com/andershfranzen/flow/blob/main/docs/EXTENDING.md" target="_blank" rel="noopener">Write your own →</a></p>
      <div v-for="p in plugins" :key="p.name" class="card">
        <div style="display:flex; gap:10px; align-items:center; flex-wrap:wrap">
          <strong style="font-size:15px">{{ p.name }}</strong>
          <span v-if="p.version" class="pill">v{{ p.version }}</span>
          <span v-if="p.error || p.manifest_error" class="pill bounce" :title="p.error || p.manifest_error">error</span>
          <span v-else-if="p.loaded" class="pill status-active">active</span>
          <span v-else-if="p.enabled" class="pill status-pending">loads on restart</span>
          <span class="spacer" style="flex:1"></span>
          <button v-if="p.settings_path || p.settings_spec?.length" class="ghost"
                  @click="toggleSettingsFor(p)">Settings</button>
          <button v-if="p.git" class="ghost" @click="upgradePlugin(p)">Update</button>
          <button class="ghost" @click="removePlugin(p)">Uninstall</button>
          <label class="choice" style="margin:0">
            <input type="checkbox" :checked="p.enabled" @change="togglePlugin(p)" /> Enabled
          </label>
        </div>
        <p v-if="p.description" style="margin:6px 0 0; color:var(--muted)">{{ p.description }}
          <span v-if="p.author"> — {{ p.author }}</span>
          <a v-if="p.url" :href="p.url" target="_blank" rel="noopener" style="display:inline-flex"><ExternalLink :size="12" /></a></p>
        <p v-if="p.error || p.manifest_error" class="error-text" style="margin:6px 0 0">{{ p.error || p.manifest_error }}</p>
        <form v-if="openSettingsFor === p.name && p.settings_spec?.length" class="plugin-settings"
              @submit.prevent="savePluginSettings(p)">
          <div v-for="f in p.settings_spec" :key="f.key" style="margin-bottom:10px">
            <label>{{ f.label || f.key }}
              <span v-if="f.type === 'password' && p.settings?.[f.key + '_set']"
                    style="text-transform:none; letter-spacing:0"> (set — blank keeps it)</span></label>
            <input v-model="pluginSettingsForm[f.key]" :type="f.type === 'password' ? 'password' : 'text'"
                   :placeholder="f.placeholder || ''" autocomplete="off" style="width:100%" />
            <p v-if="f.hint" class="hint-text" style="margin:3px 0 0; font-size:12.5px">{{ f.hint }}</p>
          </div>
          <SaveButton :saved="justSaved" />
        </form>
        <iframe v-if="openSettingsFor === p.name && p.settings_path" :src="p.settings_path"
                style="width:100%; height:420px; border:2px solid var(--border); border-radius:10px; margin-top:10px"></iframe>
      </div>
      <p v-if="!plugins.length" class="empty">No plugins installed yet.</p>
    </div>

    <!-- Profile -->
    <form v-if="tab === 'profile'" class="card" @submit.prevent="saveProfile">
      <div class="form-grid">
        <div><label>Name</label><input v-model="profile.name" style="width:100%" /></div>
        <div><label>New password</label>
          <input v-model="profile.password" type="password" autocomplete="new-password"
                 placeholder="Blank keeps current" style="width:100%" /></div>
        <div v-if="profile.password"><label>Current password</label>
          <input v-model="profile.current_password" type="password" autocomplete="current-password"
                 required style="width:100%" /></div>
        <div v-if="profile.password && otp.enabled"><label>Authenticator code</label>
          <input v-model="profile.otp_code" inputmode="numeric" autocomplete="one-time-code"
                 required style="width:100%" /></div>
        <div><label>Timezone</label>
          <StyledSelect v-model="profile.timezone" searchable style="width:100%"
                        :options="TIMEZONES" /></div>
        <div><label>Language</label>
          <StyledSelect v-model="profile.locale" style="width:100%"
                        :options="[{ value: 'en', label: 'English' }, { value: 'da', label: 'Dansk' }]" /></div>
      </div>
      <div style="margin-top:12px">
        <label>My signature (used instead of the mailbox signature)</label>
        <div class="modal-editor"><RichEditor v-model="profile.signature" placeholder="Best regards, Ada — Support" /></div>
      </div>
      <h3 style="margin-top:14px">Interface</h3>
      <label class="choice">
        <input type="checkbox" v-model="profile.ui_prefs.motion" /> Interface animations
      </label>

      <h3 style="margin-top:14px">Two-factor authentication</h3>
      <template v-if="otp.enabled">
        <p class="ok-text" style="margin:0 0 8px">Enabled — codes are required at login.</p>
        <button type="button" @click="otpDisable">Disable 2FA</button>
      </template>
      <template v-else-if="otp.setup">
        <div style="display:flex; gap:16px; align-items:flex-start; flex-wrap:wrap">
          <div v-html="otp.setup.qr_svg" style="width:150px"></div>
          <div style="flex:1; min-width:220px">
            <p class="hint-text">Scan with your authenticator app, or add the secret manually:</p>
            <code style="font-size:12px; word-break:break-all">{{ otp.setup.secret }}</code>
            <div style="display:flex; gap:8px; margin-top:10px">
              <input v-model="otp.code" placeholder="6-digit code" inputmode="numeric" style="width:130px" />
              <button type="button" class="primary" @click="otpEnable">Verify & enable</button>
            </div>
          </div>
        </div>
      </template>
      <button v-else type="button" @click="otpSetup">Enable two-factor…</button>

      <h3 style="margin-top:14px">Email notifications</h3>
      <label v-for="(label, key) in NOTIFY_LABELS" :key="key" class="choice" style="display:flex">
        <input type="checkbox" v-model="profile.notify_prefs[key]" /> {{ label }}
      </label>
      <h3 style="margin-top:14px">Muted mailboxes</h3>
      <label v-for="m in mailboxes" :key="m.id" class="choice">
        <input type="checkbox" :value="m.id" v-model="profile.muted_mailbox_ids" /> {{ m.name }}
      </label>
      <div class="form-actions"><SaveButton :saved="justSaved" :label="t.save" /></div>
    </form>

    <!-- Saved replies -->
    <div v-if="tab === 'saved_replies'">
      <div class="form-actions" style="margin:0 0 12px">
        <button v-if="session.isAdmin || mailboxes.length" class="primary"
                @click="editing = { name: '', body: '', mailbox_id: session.isAdmin ? null : mailboxes[0].id }">Add saved reply</button>
        <span class="hint" style="color:var(--muted)">Variables: <code v-pre>{{customer.name}} {{agent.name}} {{mailbox.name}}</code></span>
      </div>
      <table class="card" style="padding:0">
        <tbody>
          <tr v-for="r in savedReplies" :key="r.id">
            <td>{{ r.name }}</td>
            <td style="color:var(--muted)">{{ r.body.slice(0, 80) }}</td>
            <td style="text-align:right">
              <button v-if="session.isAdmin || r.mailbox_id" class="ghost" @click="editing = { ...r }">Edit</button>
              <button v-if="session.isAdmin || r.mailbox_id" class="ghost" @click="del(`/api/saved_replies/${r.id}`)">{{ t.delete }}</button>
            </td>
          </tr>
        </tbody>
      </table>
      <form v-if="editing" class="card" @submit.prevent="saveSavedReply">
        <div><label>Name</label><input v-model="editing.name" required style="width:100%" /></div>
        <div style="margin-top:8px"><label>Body</label><textarea v-model="editing.body" rows="5" required style="width:100%"></textarea></div>
        <div style="margin-top:8px"><label>{{ session.isAdmin ? 'Mailbox (blank = global)' : 'Mailbox' }}</label>
          <StyledSelect v-model="editing.mailbox_id" style="width:100%"
                        :options="[...(session.isAdmin ? [{ value: null, label: 'Global' }] : []), ...mailboxes.map((m) => ({ value: m.id, label: m.name }))]" /></div>
        <div class="form-actions">
          <button class="primary">{{ t.save }}</button>
          <button type="button" @click="editing = null">{{ t.cancel }}</button>
        </div>
      </form>
    </div>

    <!-- Tags -->
    <div v-if="tab === 'tags'">
      <div v-if="session.isAdmin" class="form-actions" style="margin:0 0 12px">
        <button class="primary" @click="editing = { name: '', color: '#2563eb' }">Add tag</button>
      </div>
      <table class="card" style="padding:0">
        <tbody>
          <tr v-for="x in tags" :key="x.id">
            <td><span class="tag-pill" :style="{ background: x.color }">{{ x.name }}</span></td>
            <td style="color:var(--muted); font-family: ui-monospace, Menlo, monospace; font-size:13px">{{ x.color }}</td>
            <td style="text-align:right">
              <button v-if="session.isAdmin" class="ghost" @click="editing = { ...x }">{{ t.edit }}</button>
              <button v-if="session.isAdmin" class="ghost" @click="del(`/api/tags/${x.id}`)">{{ t.delete }}</button>
            </td>
          </tr>
          <tr v-if="!tags.length"><td style="color:var(--muted)">No tags yet</td></tr>
        </tbody>
      </table>
      <form v-if="editing && session.isAdmin" class="card" @submit.prevent="saveTag">
        <h3>{{ editing.id ? 'Edit tag' : 'New tag' }}</h3>
        <div style="display:flex; align-items:flex-end; gap:14px">
          <div style="flex:1"><label>Name</label><input v-model="editing.name" required style="width:100%" /></div>
          <div><label>Colour</label>
            <span class="swatch-wrap">
              <button type="button" class="swatch" :style="{ background: editing.color }"
                      aria-label="Pick tag colour" @click="openPicker = openPicker === 'tag' ? null : 'tag'" />
              <ColorPicker v-if="openPicker === 'tag'" :model-value="editing.color"
                           @update:model-value="(v) => (editing.color = v)" @close="openPicker = null" />
            </span>
          </div>
          <div style="flex:1"><span class="tag-pill" :style="{ background: editing.color }">{{ editing.name || 'preview' }}</span></div>
        </div>
        <div class="form-actions">
          <button class="primary">{{ t.save }}</button>
          <button v-if="editing.id && session.isAdmin" type="button" @click="del(`/api/tags/${editing.id}`); editing = null">{{ t.delete }}</button>
          <button type="button" @click="editing = null">{{ t.cancel }}</button>
        </div>
      </form>
    </div>

    <!-- Webhooks -->
    <div v-if="tab === 'webhooks'">
      <div class="form-actions" style="margin:0 0 12px">
        <button class="primary" @click="editing = { url: '', events: [], enabled: true }">Add webhook</button>
      </div>
      <table class="card" style="padding:0">
        <tbody>
          <tr v-for="w in webhooks" :key="w.id">
            <td>{{ w.url }}</td>
            <td style="color:var(--muted)">{{ w.events.length ? w.events.join(', ') : 'all events' }}</td>
            <td><span class="pill" :class="w.enabled ? 'status-active' : ''">{{ w.enabled ? 'on' : 'off' }}</span></td>
            <td style="text-align:right">
              <button class="ghost" @click="editing = { ...w }">Edit</button>
              <button class="ghost" @click="del(`/api/webhooks/${w.id}`)">{{ t.delete }}</button>
            </td>
          </tr>
        </tbody>
      </table>
      <form v-if="editing" class="card" @submit.prevent="saveWebhook">
        <div><label>URL</label><input v-model="editing.url" required placeholder="https://…" style="width:100%" /></div>
        <div style="margin-top:8px">
          <label>Events (none = all)</label>
          <TogglePills v-model="editing.events" :options="WEBHOOK_EVENTS" />
        </div>
        <div style="margin-top:8px"><label class="choice"><input type="checkbox" v-model="editing.enabled" /> Enabled</label></div>
        <p v-if="editing.secret" style="font-size:12px; color:var(--muted)">Secret: <code>{{ editing.secret }}</code></p>
        <div class="form-actions">
          <button class="primary">{{ t.save }}</button>
          <button type="button" @click="editing = null">{{ t.cancel }}</button>
        </div>
      </form>
    </div>

    <!-- API tokens -->
    <div v-if="tab === 'tokens'">
      <div class="form-actions" style="margin:0 0 12px">
        <button class="primary" @click="editing = { name: '', scope: 'read', current_password: '', otp_code: '' }; newToken = null">New token</button>
      </div>
      <p v-if="newToken" class="card ok-text">
        Token created — copy it now, it is shown once:<br /><code>{{ newToken.token }}</code>
      </p>
      <table class="card" style="padding:0">
        <tbody>
          <tr v-for="x in tokens" :key="x.id">
            <td>{{ x.name }}</td><td><span class="pill">{{ x.scope }}</span></td>
            <td style="color:var(--muted)">{{ x.last_used_at ? `used ${new Date(x.last_used_at).toLocaleDateString()}` : 'never used' }}</td>
            <td style="color:var(--muted)">expires {{ new Date(x.expires_at).toLocaleDateString() }}</td>
            <td style="text-align:right"><button class="ghost" @click="del(`/api/api_tokens/${x.id}`)">Revoke</button></td>
          </tr>
        </tbody>
      </table>
      <form v-if="editing" class="card" @submit.prevent="createToken">
        <div class="form-grid">
          <div><label>Name</label><input v-model="editing.name" required style="width:100%" /></div>
          <div><label>Scope</label>
            <StyledSelect v-model="editing.scope" style="width:100%"
                          :options="[{ value: 'read', label: 'Read only' }, { value: 'write', label: 'Read + write' }]" /></div>
          <div><label>Current password</label>
            <input v-model="editing.current_password" type="password" autocomplete="current-password"
                   required style="width:100%" /></div>
          <div v-if="otp.enabled"><label>Authenticator code</label>
            <input v-model="editing.otp_code" inputmode="numeric" autocomplete="one-time-code"
                   required style="width:100%" /></div>
        </div>
        <div class="form-actions">
          <button class="primary">Create</button>
          <button type="button" @click="editing = null">{{ t.cancel }}</button>
        </div>
      </form>
    </div>
  </main>
</template>
