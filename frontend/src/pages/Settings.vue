<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useSession } from '../stores/session'
import { api } from '../api'
import { t, setLocale } from '../strings'
import WorkflowBuilder from '../components/WorkflowBuilder.vue'
import RichEditor from '../components/RichEditor.vue'
import ReportsPanel from '../components/ReportsPanel.vue'

const props = defineProps({ tab: String })
const router = useRouter()
const session = useSession()

const TABS = computed(() => {
  const base = [['profile', 'My profile'], ['saved_replies', 'Saved replies'], ['tags', 'Tags'], ['tokens', 'API tokens']]
  const admin = [['org', 'Organisation'], ['agents', 'Agents'], ['teams', 'Teams'], ['mailboxes', 'Mailboxes'], ['workflows', 'Workflows'], ['reports', 'Reports'], ['webhooks', 'Webhooks'], ['plugins', 'Plugins']]
  return session.isAdmin ? [...admin, ...base] : base
})
const tab = computed(() => props.tab || (session.isAdmin ? 'org' : 'profile'))

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

const profile = ref({ name: '', password: '', notify_prefs: {}, muted_mailbox_ids: [] })
const teams = ref([])
const plugins = ref([])
const restartHint = ref('')
const installUrl = ref('')
const openSettingsFor = ref(null)
const pluginBusy = ref(false)
const otp = ref({ setup: null, code: '', enabled: false })

async function load() {
  flash.value = ''
  editing.value = null
  if (tab.value === 'org' && session.isAdmin) org.value = await api.get('/api/org_settings')
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
  if (tab.value === 'tokens') tokens.value = await api.get('/api/api_tokens')
  if (tab.value === 'profile') {
    const me = await api.get('/api/me')
    otp.value = { setup: null, code: '', enabled: !!me.otp_required }
    mailboxes.value = await api.get('/api/mailboxes')
    profile.value = { name: me.name, password: '', locale: me.locale, timezone: me.timezone,
                      signature: me.signature || '',
                      notify_prefs: me.notify_prefs, ui_prefs: { motion: true, ...(me.ui_prefs || {}) },
                      muted_mailbox_ids: me.muted_mailbox_ids || [] }
  }
}
onMounted(load)
watch(tab, load)

function ok(msg = 'Saved') { flash.value = msg; setTimeout(() => (flash.value = ''), 2500) }

async function saveOrg() { org.value = await api.patch('/api/org_settings', org.value); ok() }

async function saveProfile() {
  await api.patch('/api/me', profile.value)
  profile.value.password = ''
  setLocale(profile.value.locale)
  if (session.agent) session.agent.locale = profile.value.locale
  document.body.classList.toggle('no-motion', profile.value.ui_prefs.motion === false)
  ok()
}

async function otpSetup() { otp.value.setup = await api.post('/api/me/2fa/setup') }
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
  if (w.id) await api.patch(`/api/webhooks/${w.id}`, w)
  else await api.post('/api/webhooks', w)
  await load(); ok()
}
async function createToken() {
  newToken.value = await api.post('/api/api_tokens', editing.value)
  await load()
}
async function del(path) { await api.delete(path); await load() }

async function togglePlugin(p) {
  const data = await api.patch(`/api/plugins/${p.name}`, { enabled: !p.enabled })
  plugins.value = data.plugins
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

const WEBHOOK_EVENTS = ['thread.created', 'message.inbound', 'message.outbound', 'thread.assigned', 'thread.status']
const NOTIFY_LABELS = {
  new_unassigned: 'New unassigned conversation',
  assigned_to_me: 'Conversation assigned to me',
  customer_reply: 'Customer replies on mine',
  note_on_mine: 'Note added on mine',
}
</script>

<template>
  <main class="settings-wrap">
    <p><router-link to="/inbox">← Inbox</router-link></p>
    <h1>{{ t.settings }}</h1>
    <nav class="settings-tabs">
      <button v-for="[key, label] in TABS" :key="key" :class="{ active: tab === key }"
              @click="router.push(`/settings/${key}`)">{{ label }}</button>
    </nav>
    <p v-if="flash" class="ok-text">{{ flash }}</p>

    <!-- Org -->
    <form v-if="tab === 'org'" class="card" @submit.prevent="saveOrg">
      <div class="form-grid">
        <div><label>Site name</label><input v-model="org.site_name" style="width:100%" /></div>
        <div><label>Base URL</label><input v-model="org.base_url" placeholder="https://inbox.example.com" style="width:100%" /></div>
        <div><label>Notify from (email)</label><input v-model="org.notify_from" style="width:100%" /></div>
      </div>
      <h3 style="margin-top:16px">Microsoft 365 OAuth app</h3>
      <p class="hint-text">Register an app in Entra ID with delegated IMAP.AccessAsUser.All + SMTP.Send permissions and redirect URI <code>{{ org.base_url || '&lt;base url&gt;' }}/oauth/callback</code>.</p>
      <div class="form-grid">
        <div><label>Client ID</label><input v-model="org.ms_client_id" style="width:100%" /></div>
        <div><label>Client secret {{ org.ms_client_secret_set ? '(set — blank keeps it)' : '' }}</label>
          <input v-model="org.ms_client_secret" type="password" style="width:100%" /></div>
        <div><label>Tenant (or "common")</label><input v-model="org.ms_tenant" style="width:100%" /></div>
      </div>
      <h3 style="margin-top:16px">Google OAuth app</h3>
      <p class="hint-text">Google Cloud OAuth client (web), scope <code>https://mail.google.com/</code>, same redirect URI.</p>
      <div class="form-grid">
        <div><label>Client ID</label><input v-model="org.google_client_id" style="width:100%" /></div>
        <div><label>Client secret {{ org.google_client_secret_set ? '(set — blank keeps it)' : '' }}</label>
          <input v-model="org.google_client_secret" type="password" style="width:100%" /></div>
      </div>
      <div class="form-actions"><button class="primary">{{ t.save }}</button></div>
    </form>

    <!-- Agents -->
    <div v-if="tab === 'agents'">
      <div class="form-actions" style="margin:0 0 12px"><button class="primary" @click="newAgent">Add agent</button></div>
      <table class="card" style="padding:0">
        <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Mailboxes</th><th></th></tr></thead>
        <tbody>
          <tr v-for="a in agents" :key="a.id">
            <td>{{ a.name }}</td><td>{{ a.email }}</td><td>{{ a.role }}</td>
            <td>{{ a.role === 'admin' ? 'all' : a.mailbox_ids.length }}</td>
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
            <select v-model="editing.role" style="width:100%"><option value="user">user</option><option value="admin">admin</option></select></div>
        </div>
        <div v-if="editing.role !== 'admin'" style="margin-top:10px">
          <label>Mailbox access</label>
          <label v-for="m in mailboxes" :key="m.id" class="choice">
            <input type="checkbox" :value="m.id" v-model="editing.mailbox_ids" /> {{ m.name }}
          </label>
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
          <label v-for="a in agents" :key="a.id" class="choice">
            <input type="checkbox" :value="a.id" v-model="editing.agent_ids" /> {{ a.name }}
          </label>
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
            <select v-model="editing.auth_kind" style="width:100%">
              <option value="password">Password (IMAP/SMTP)</option>
              <option value="microsoft">Microsoft 365 (OAuth)</option>
              <option value="google">Google (OAuth)</option>
            </select></div>
          <div v-if="editing.auth_kind !== 'password'" style="align-self:end; display:flex; gap:8px; align-items:center">
            <button type="button" class="primary" @click="connectOauth">
              Connect {{ editing.auth_kind === 'microsoft' ? 'Microsoft 365' : 'Google' }}
            </button>
            <span v-if="editing.oauth_connected" class="pill status-active">connected</span>
            <span v-else class="pill">not connected</span>
          </div>
        </div>
        <h3 style="margin-top:14px">IMAP (incoming)</h3>
        <div class="form-grid">
          <div><label>Host</label><input v-model="editing.imap_host" style="width:100%" /></div>
          <div><label>Port</label><input v-model.number="editing.imap_port" type="number" style="width:100%" /></div>
          <div><label>User</label><input v-model="editing.imap_user" style="width:100%" /></div>
          <div v-if="editing.auth_kind === 'password'"><label>Password {{ editing.imap_password_set ? '(set — blank keeps it)' : '' }}</label>
            <input v-model="editing.imap_password" type="password" style="width:100%" /></div>
          <div><label>Folder</label><input v-model="editing.imap_folder" style="width:100%" /></div>
          <div style="align-self:end"><label class="choice"><input type="checkbox" v-model="editing.imap_ssl" /> SSL</label></div>
        </div>
        <h3 style="margin-top:14px">SMTP (outgoing)</h3>
        <div class="form-grid">
          <div><label>Host</label><input v-model="editing.smtp_host" style="width:100%" /></div>
          <div><label>Port</label><input v-model.number="editing.smtp_port" type="number" style="width:100%" /></div>
          <div><label>User</label><input v-model="editing.smtp_user" style="width:100%" /></div>
          <div v-if="editing.auth_kind === 'password'"><label>Password {{ editing.smtp_password_set ? '(set — blank keeps it)' : '' }}</label>
            <input v-model="editing.smtp_password" type="password" style="width:100%" /></div>
          <div><label>Security</label>
            <select v-model="editing.smtp_security" style="width:100%">
              <option value="starttls">STARTTLS</option><option value="ssl">SSL/TLS</option><option value="none">None</option>
            </select></div>
        </div>
        <h3 style="margin-top:14px">Auto-reply</h3>
        <label class="choice"><input type="checkbox" v-model="editing.auto_reply_enabled" /> Send "we got your mail" once per new conversation</label>
        <textarea v-if="editing.auto_reply_enabled" v-model="editing.auto_reply_body" rows="3" style="width:100%"
                  placeholder="Thanks — we received your message and will reply soon."></textarea>
        <div style="margin-top:10px"><label>Signature (appended to replies — formatting and logos supported)</label>
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
      <form class="card" @submit.prevent="installPlugin" style="display:flex; gap:8px; align-items:end">
        <div style="flex:1">
          <label>Install from git URL</label>
          <input v-model="installUrl" required placeholder="https://github.com/someone/flow-plugin-example.git" style="width:100%" />
        </div>
        <button class="primary" :disabled="pluginBusy">Install</button>
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
          <button v-if="p.settings_path" class="ghost" @click="openSettingsFor = openSettingsFor === p.name ? null : p.name">Settings</button>
          <button v-if="p.git" class="ghost" @click="upgradePlugin(p)">Update</button>
          <button class="ghost" @click="removePlugin(p)">Uninstall</button>
          <label class="choice" style="margin:0">
            <input type="checkbox" :checked="p.enabled" @change="togglePlugin(p)" /> Enabled
          </label>
        </div>
        <p v-if="p.description" style="margin:6px 0 0; color:var(--muted)">{{ p.description }}
          <span v-if="p.author"> — {{ p.author }}</span>
          <a v-if="p.url" :href="p.url" target="_blank" rel="noopener">↗</a></p>
        <p v-if="p.error || p.manifest_error" class="error-text" style="margin:6px 0 0">{{ p.error || p.manifest_error }}</p>
        <iframe v-if="openSettingsFor === p.name && p.settings_path" :src="p.settings_path"
                style="width:100%; height:420px; border:2px solid var(--border); border-radius:10px; margin-top:10px"></iframe>
      </div>
      <p v-if="!plugins.length" class="empty">No plugins installed yet.</p>
    </div>

    <!-- Profile -->
    <form v-if="tab === 'profile'" class="card" @submit.prevent="saveProfile">
      <div class="form-grid">
        <div><label>Name</label><input v-model="profile.name" style="width:100%" /></div>
        <div><label>New password (blank keeps current)</label>
          <input v-model="profile.password" type="password" style="width:100%" /></div>
        <div><label>Timezone</label><input v-model="profile.timezone" style="width:100%" /></div>
        <div><label>Language</label>
          <select v-model="profile.locale" style="width:100%">
            <option value="en">English</option>
            <option value="da">Dansk</option>
          </select></div>
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
      <div class="form-actions"><button class="primary">{{ t.save }}</button></div>
    </form>

    <!-- Saved replies -->
    <div v-if="tab === 'saved_replies'">
      <div class="form-actions" style="margin:0 0 12px">
        <button class="primary" @click="editing = { name: '', body: '', mailbox_id: null }">Add saved reply</button>
        <span class="hint" style="color:var(--muted)">Variables: <code v-pre>{{customer.name}} {{agent.name}} {{mailbox.name}}</code></span>
      </div>
      <table class="card" style="padding:0">
        <tbody>
          <tr v-for="r in savedReplies" :key="r.id">
            <td>{{ r.name }}</td>
            <td style="color:var(--muted)">{{ r.body.slice(0, 80) }}</td>
            <td style="text-align:right">
              <button class="ghost" @click="editing = { ...r }">Edit</button>
              <button class="ghost" @click="del(`/api/saved_replies/${r.id}`)">{{ t.delete }}</button>
            </td>
          </tr>
        </tbody>
      </table>
      <form v-if="editing" class="card" @submit.prevent="saveSavedReply">
        <div><label>Name</label><input v-model="editing.name" required style="width:100%" /></div>
        <div style="margin-top:8px"><label>Body</label><textarea v-model="editing.body" rows="5" required style="width:100%"></textarea></div>
        <div style="margin-top:8px"><label>Mailbox (blank = global)</label>
          <select v-model="editing.mailbox_id" style="width:100%">
            <option :value="null">Global</option>
            <option v-for="m in mailboxes" :key="m.id" :value="m.id">{{ m.name }}</option>
          </select></div>
        <div class="form-actions">
          <button class="primary">{{ t.save }}</button>
          <button type="button" @click="editing = null">{{ t.cancel }}</button>
        </div>
      </form>
    </div>

    <!-- Tags -->
    <div v-if="tab === 'tags'">
      <div class="form-actions" style="margin:0 0 12px">
        <button class="primary" @click="editing = { name: '', color: '#2563eb' }">Add tag</button>
      </div>
      <div class="card" style="display:flex; gap:8px; flex-wrap:wrap">
        <span v-for="x in tags" :key="x.id" class="tag-pill" :style="{ background: x.color, cursor: 'pointer' }"
              @click="editing = { ...x }">{{ x.name }}</span>
        <span v-if="!tags.length" style="color:var(--muted)">No tags yet</span>
      </div>
      <form v-if="editing" class="card" @submit.prevent="saveTag">
        <div class="form-grid">
          <div><label>Name</label><input v-model="editing.name" required style="width:100%" /></div>
          <div><label>Colour</label><input v-model="editing.color" type="color" /></div>
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
          <label v-for="e in WEBHOOK_EVENTS" :key="e" class="choice">
            <input type="checkbox" :value="e" v-model="editing.events" /> {{ e }}
          </label>
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
        <button class="primary" @click="editing = { name: '', scope: 'read' }; newToken = null">New token</button>
      </div>
      <p v-if="newToken" class="card ok-text">
        Token created — copy it now, it is shown once:<br /><code>{{ newToken.token }}</code>
      </p>
      <table class="card" style="padding:0">
        <tbody>
          <tr v-for="x in tokens" :key="x.id">
            <td>{{ x.name }}</td><td><span class="pill">{{ x.scope }}</span></td>
            <td style="color:var(--muted)">{{ x.last_used_at ? `used ${new Date(x.last_used_at).toLocaleDateString()}` : 'never used' }}</td>
            <td style="text-align:right"><button class="ghost" @click="del(`/api/api_tokens/${x.id}`)">Revoke</button></td>
          </tr>
        </tbody>
      </table>
      <form v-if="editing" class="card" @submit.prevent="createToken">
        <div class="form-grid">
          <div><label>Name</label><input v-model="editing.name" required style="width:100%" /></div>
          <div><label>Scope</label>
            <select v-model="editing.scope" style="width:100%"><option value="read">read</option><option value="write">write</option></select></div>
        </div>
        <div class="form-actions">
          <button class="primary">Create</button>
          <button type="button" @click="editing = null">{{ t.cancel }}</button>
        </div>
      </form>
    </div>
  </main>
</template>
