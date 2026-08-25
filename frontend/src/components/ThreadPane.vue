<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { useSession } from '../stores/session'
import { useInbox } from '../stores/inbox'
import { api } from '../api'
import { t } from '../strings'
import Composer from './Composer.vue'
import { avatarColor, initials } from '../avatar'
import Attachments from './Attachments.vue'
import { shortTime, fullTime } from '../format'

const router = useRouter()
const session = useSession()
const inbox = useInbox()

const agents = ref([])
const tags = ref([])
const forwardSeed = ref(null)
const customerDetail = ref(null)
const editingCustomer = ref(false)
const customerForm = ref({})
// Insights sidebar visibility persists across threads and reloads.
const showInsights = ref(localStorage.getItem('flow:insights') !== 'off')
function toggleInsights() {
  showInsights.value = !showInsights.value
  localStorage.setItem('flow:insights', showInsights.value ? 'on' : 'off')
}
const transcriptEl = ref(null)
let heartbeatTimer = null

const conv = computed(() => inbox.current)

// Messages + events merged, newest-last (B2).
const timeline = computed(() => {
  if (!conv.value) return []
  const items = [
    ...(conv.value.messages || []).map((m) => ({ ...m, _type: 'message' })),
    ...(conv.value.events || []).map((e) => ({ ...e, _type: 'event' })),
  ]
  return items.sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
})

async function heartbeat() {
  if (!conv.value) return
  try {
    const data = await api.post(`/api/conversations/${conv.value.id}/presence`)
    inbox.viewers = data.viewers
  } catch {}
}

onMounted(async () => {
  agents.value = await api.get('/api/agents')
  tags.value = await api.get('/api/tags')
  heartbeat()
  heartbeatTimer = setInterval(heartbeat, 5000)
})
onUnmounted(() => clearInterval(heartbeatTimer))

watch(() => conv.value?.messages_count, async () => {
  await nextTick()
  transcriptEl.value?.scrollTo?.(0, transcriptEl.value.scrollHeight)
})

function setStatus(status) { inbox.update(conv.value.id, { status }) }
function setAssignee(e) { inbox.update(conv.value.id, { assignee_id: e.target.value || null }) }
function toggleStar() { inbox.update(conv.value.id, { starred: !conv.value.starred }) }
async function toggleFollow() {
  if (conv.value.followed) await api.delete(`/api/conversations/${conv.value.id}/follow`)
  else await api.post(`/api/conversations/${conv.value.id}/follow`)
  conv.value.followed = !conv.value.followed
}
function toggleTag(tag) {
  const ids = conv.value.tags.map((x) => x.id)
  const next = ids.includes(tag.id) ? ids.filter((x) => x !== tag.id) : [...ids, tag.id]
  inbox.update(conv.value.id, { tag_ids: next })
}
async function loadCustomer() {
  if (!conv.value) return
  customerDetail.value = await api.get(`/api/customers/${conv.value.customer.id}`)
}
watch(() => conv.value?.customer?.id, (id) => { if (id) loadCustomer() }, { immediate: true })

function startEditCustomer() {
  const c = customerDetail.value || conv.value.customer
  customerForm.value = { name: c.name || '', company: c.company || '',
                         phone: (c.phones || [])[0] || '', notes: c.notes || '' }
  editingCustomer.value = true
}

async function saveCustomer() {
  const f = customerForm.value
  await api.patch(`/api/customers/${conv.value.customer.id}`, {
    name: f.name, company: f.company, notes: f.notes, phones: f.phone ? [f.phone] : [],
  })
  editingCustomer.value = false
  await loadCustomer()
  conv.value.customer.name = f.name
}

async function mergeCustomer() {
  const email = window.prompt(`${t.mergeCustomer}\nEmail address of the duplicate customer:`)
  if (!email) return
  try {
    customerDetail.value = await api.post(`/api/customers/${conv.value.customer.id}/merge`, { source_email: email.trim() })
  } catch (e) {
    alert(e.status === 404 ? 'No customer with that address' : 'Merge failed')
  }
}

// Merged conversations redirect to their target (B14).
watch(() => conv.value?.merged_into_id, (id) => {
  if (id) router.replace(`/conversations/${id}`)
}, { immediate: true })

function closeMenus() {
  document.querySelectorAll('details[open]').forEach((d) => (d.open = false))
}

async function addToPersonalFolder(e) {
  closeMenus()
  const id = e.target.value
  e.target.value = ''
  if (!id) return
  await api.post(`/api/personal_folders/${id}/items`, { conversation_ids: [conv.value.id] })
  await inbox.loadPersonalFolders()
}

async function mergeInto() {
  closeMenus()
  const number = window.prompt('Merge this conversation into #…\nEnter the target conversation number:')
  if (!number) return
  const target = await api.post(`/api/conversations/${conv.value.id}/merge`, { into_number: Number(number.replace('#', '')) })
  await inbox.loadConversations()
  router.replace(`/conversations/${target.id}`)
}

async function moveTo(e) {
  closeMenus()
  const id = e.target.value
  e.target.value = ''
  if (!id) return
  await inbox.update(conv.value.id, { mailbox_id: Number(id) })
}

function snoozeUntil(e) {
  closeMenus()
  const choice = e.target.value
  e.target.value = ''
  if (!choice) return
  const d = new Date()
  if (choice === 'tomorrow') { d.setDate(d.getDate() + 1); d.setHours(9, 0, 0, 0) }
  else if (choice === '3days') { d.setDate(d.getDate() + 3); d.setHours(9, 0, 0, 0) }
  else if (choice === 'monday') { d.setDate(d.getDate() + ((8 - d.getDay()) % 7 || 7)); d.setHours(9, 0, 0, 0) }
  else if (choice === 'wake') { inbox.update(conv.value.id, { snooze_until: null }); return }
  inbox.update(conv.value.id, { snooze_until: d.toISOString() })
}

function startForward() {
  closeMenus()
  const last = [...(conv.value.messages || [])].reverse().find((m) => m.kind !== 'note')
  forwardSeed.value = {
    subject: `Fwd: ${conv.value.subject}`,
    body: `\n\n---------- Forwarded message ----------\nFrom: ${last?.from_email || conv.value.customer.email}\nSubject: ${conv.value.subject}\n\n${last?.body_text || ''}`,
  }
}

async function undoSend(message) {
  const data = await api.delete(`/api/conversations/${conv.value.id}/messages/${message.id}`)
  forwardSeed.value = { subject: null, body: '', html: data.body, keepTo: true }
  await inbox.open(conv.value.id)
}

async function onSent() {
  await inbox.open(conv.value.id)
  await inbox.loadConversations()
}

// Inline images: rewrite cid: to attachment URLs (A20 display side).
// Quoted history and signatures collapse behind a native <details> toggle.
const QUOTE_SELECTOR = 'blockquote, .gmail_quote, [id^="divRplyFwdMsg"], [id^="appendonsend"], .OutlookMessageHeader, .moz-cite-prefix'
const TEXT_QUOTE_MARKERS = [
  /^>/, /^On .{0,200}wrote:\s*$/, /^-{2,}\s*Original Message\s*-{0,}/i,
  /^Den .{0,200}skrev\b/, /^Fra:\s/, /^From:\s/, /^-- $/, /^_{10,}\s*$/,
]

function renderHtml(m) {
  let html = m.body_html || ''
  for (const a of m.attachments || []) {
    if (a.content_id) html = html.replaceAll(`cid:${a.content_id}`, a.url)
  }
  try {
    const doc = new DOMParser().parseFromString(html, 'text/html')
    const first = doc.body.querySelector(QUOTE_SELECTOR)
    if (first && first.textContent.trim()) {
      const details = doc.createElement('details')
      details.className = 'quoted'
      details.innerHTML = '<summary>•••</summary>'
      let node = first
      const trail = []
      while (node) { trail.push(node); node = node.nextElementSibling }
      first.parentNode.insertBefore(details, first)
      trail.forEach((n) => details.appendChild(n))
    }
    return doc.body.innerHTML
  } catch { return html }
}

function splitText(text) {
  const lines = (text || '').split('\n')
  for (let i = 1; i < lines.length; i++) {
    if (TEXT_QUOTE_MARKERS.some((re) => re.test(lines[i]))) {
      return { main: lines.slice(0, i).join('\n').trimEnd(), quoted: lines.slice(i).join('\n') }
    }
  }
  return { main: text, quoted: null }
}

function eventText(e) {
  if (e.kind === 'assigned') return `${e.agent?.name || 'Someone'} assigned to ${e.data.assignee_name}`
  if (e.kind === 'unassigned') return `${e.agent?.name || 'Someone'} unassigned`
  if (e.kind === 'status_changed') return `${e.agent?.name || ''} marked ${t.statuses[e.data.status] || e.data.status}`.trim()
  return e.kind
}
</script>

<template>
  <section v-if="conv" class="pane" aria-label="Conversation">
    <header class="pane-head">
      <div class="head-row">
        <button class="ghost" @click="router.push('/inbox')" data-tip="Back to list">←</button>
        <h2 class="head-title" :title="conv.subject">
          <span class="number">#{{ conv.number }}</span>
          {{ conv.subject || '(no subject)' }}
        </h2>
        <button class="ghost star-btn" :class="{ starred: conv.starred }" @click="toggleStar"
                :data-tip="conv.starred ? 'Unstar' : 'Star'">
          {{ conv.starred ? '★' : '☆' }}
        </button>
        <button class="ghost insights-toggle" @click="toggleInsights"
                :data-tip="showInsights ? `Hide ${t.insights.toLowerCase()}` : `Show ${t.insights.toLowerCase()}`"
                :aria-expanded="showInsights">◨</button>
      </div>
      <div class="head-controls">
        <button type="button" class="pill follow-pill" :class="{ on: conv.followed }" @click="toggleFollow">
          {{ conv.followed ? t.following : t.follow }}
        </button>
        <select :value="conv.assignee?.id || ''" @change="setAssignee" :aria-label="t.assignTo">
          <option value="">{{ t.unassigned }}</option>
          <option v-for="a in agents" :key="a.id" :value="a.id">{{ a.name }}</option>
        </select>
        <select :value="conv.status" @change="setStatus($event.target.value)" aria-label="Status">
          <option v-for="(label, s) in t.statuses" :key="s" :value="s">{{ label }}</option>
        </select>
        <details class="tag-menu">
          <summary class="pill" style="cursor:pointer">{{ t.tags }}</summary>
          <div class="card menu-card">
            <label v-for="tag in tags" :key="tag.id" class="choice" style="display:flex; margin-right:0">
              <input type="checkbox" :checked="conv.tags.some((x) => x.id === tag.id)" @change="toggleTag(tag)" />
              <span class="tag-pill" :style="{ background: tag.color }">{{ tag.name }}</span>
            </label>
            <span v-if="!tags.length" class="hint" style="font-size:12px; color:var(--muted)">No tags yet — create them in Settings</span>
          </div>
        </details>
        <details class="tag-menu">
          <summary class="pill" style="cursor:pointer">⋯</summary>
          <div class="card menu-card" style="display:flex; flex-direction:column; gap:6px; min-width:190px">
            <button type="button" class="ghost" style="text-align:left" @click="startForward">Forward…</button>
            <button type="button" class="ghost" style="text-align:left" @click="mergeInto">Merge into #…</button>
            <select v-if="inbox.personalFolders.length" @change="addToPersonalFolder" aria-label="Add to personal folder">
              <option value="">Add to my folder…</option>
              <option v-for="pf in inbox.personalFolders" :key="pf.id" :value="pf.id">{{ pf.name }}</option>
            </select>
            <select @change="snoozeUntil" aria-label="Snooze">
              <option value="">Snooze…</option>
              <option value="tomorrow">Until tomorrow 09:00</option>
              <option value="3days">For 3 days</option>
              <option value="monday">Until Monday 09:00</option>
              <option v-if="conv.snoozed_until" value="wake">Unsnooze</option>
            </select>
            <select v-if="inbox.mailboxes.length > 1" @change="moveTo" aria-label="Move to mailbox">
              <option value="">Move to…</option>
              <option v-for="m in inbox.mailboxes.filter((x) => x.id !== conv.mailbox_id)" :key="m.id" :value="m.id">{{ m.name }}</option>
            </select>
          </div>
        </details>
      </div>
    </header>

    <div class="pane-body">
      <div class="transcript-col" ref="transcriptEl">
        <div class="transcript">
          <div v-if="inbox.viewers.length" class="collision" style="margin-bottom:12px">
            👀 {{ inbox.viewers.map((v) => v.name).join(', ') }} {{ t.viewing }}
          </div>
        <template v-for="item in timeline" :key="item._type + item.id">
          <div v-if="item._type === 'event'" class="event-line">{{ eventText(item) }} · {{ shortTime(item.created_at) }}</div>
          <article v-else class="msg" :class="item.kind">
            <div class="msg-head">
              <span class="who-line">
                <span class="from">{{ item.kind === 'inbound' ? (item.from_name || item.from_email) : (item.agent?.name || 'Agent') }}</span>
                <span v-if="item.kind === 'note'"> · {{ t.internalNote }}</span>
                <span v-else-if="item.kind === 'outbound'"> → {{ (item.to || []).join(', ') }}</span>
              </span>
              <span class="when-line">
                <span v-if="item.bounce" class="pill bounce">{{ t.bounced }}</span>
                <span v-if="item.status === 'queued'" class="pill">{{ t.queued }}</span>
                <button v-if="item.status === 'queued' && item.kind === 'outbound'" type="button"
                        class="ghost" style="padding:0 8px; font-size:12px" data-tip="Cancel before it sends" @click="undoSend(item)">Undo</button>
                <span v-if="item.status === 'failed'" class="pill bounce">{{ t.failed }}</span>
                <time :title="fullTime(item.created_at)">{{ shortTime(item.created_at) }}</time>
              </span>
            </div>
            <div v-if="item.body_html" class="msg-body" dir="auto" v-html="renderHtml(item)"></div>
            <div v-else class="msg-body" dir="auto" style="white-space:pre-wrap">{{ splitText(item.body_text).main }}<details v-if="splitText(item.body_text).quoted" class="quoted"><summary>•••</summary>{{ splitText(item.body_text).quoted }}</details></div>
            <Attachments :attachments="item.attachments || []" />
          </article>
        </template>

          <Composer :conversation="conv" :forward-seed="forwardSeed" @sent="onSent" />
        </div>
      </div>

      <aside class="side-panel" :class="{ collapsed: !showInsights }" :aria-label="t.insights">
        <div class="insights-inner">
        <div class="insights-head">
          <span>{{ t.insights }}</span>
          <button class="ghost" style="padding:2px 8px" :data-tip="`Hide ${t.insights.toLowerCase()}`"
                  @click="toggleInsights">»</button>
        </div>
        <div class="card">
          <h3 style="display:flex; justify-content:space-between; align-items:center">
            {{ t.customer }}
            <button v-if="!editingCustomer" class="ghost" style="padding:2px 8px; font-size:12px" @click="startEditCustomer">{{ t.edit }}</button>
          </h3>
          <div style="display:flex; gap:10px; align-items:center">
            <span class="avatar" :style="{ background: avatarColor(conv.customer.email) }">
              {{ initials(conv.customer.name || conv.customer.email) }}
            </span>
            <div style="min-width:0">
              <div style="font-weight:700">{{ customerDetail?.name || conv.customer.name || '—' }}</div>
              <div style="color:var(--muted); font-size:13px; overflow-wrap:anywhere">{{ conv.customer.email }}</div>
            </div>
          </div>
          <template v-if="editingCustomer">
            <div style="display:flex; flex-direction:column; gap:6px; margin-top:10px">
              <input v-model="customerForm.name" :placeholder="t.customer" />
              <input v-model="customerForm.company" :placeholder="t.company" />
              <input v-model="customerForm.phone" :placeholder="t.phone" />
              <textarea v-model="customerForm.notes" rows="2" :placeholder="t.notes"></textarea>
              <div style="display:flex; gap:6px">
                <button class="primary" style="padding:4px 12px" @click="saveCustomer">{{ t.save }}</button>
                <button class="ghost" style="padding:4px 8px" @click="editingCustomer = false">{{ t.cancel }}</button>
              </div>
            </div>
          </template>
          <template v-else-if="customerDetail">
            <div v-if="customerDetail.company" style="font-size:13px; margin-top:6px">🏢 {{ customerDetail.company }}</div>
            <div v-if="(customerDetail.phones || []).length" style="font-size:13px">📞 {{ customerDetail.phones.join(', ') }}</div>
            <div v-if="(customerDetail.emails || []).length" style="font-size:12px; color:var(--muted)">also: {{ customerDetail.emails.join(', ') }}</div>
            <div v-if="customerDetail.notes" style="font-size:13px; color:var(--muted); margin-top:4px; white-space:pre-wrap">{{ customerDetail.notes }}</div>
          </template>
          <button class="ghost" style="margin-top:8px; padding:2px 8px; font-size:12px" @click="mergeCustomer">{{ t.mergeCustomer }}</button>
        </div>
        <div v-if="(customerDetail?.conversations || []).filter((c) => c.id !== conv.id).length" class="card">
          <h3>{{ t.previousConversations }}</h3>
          <div v-for="pc in customerDetail.conversations.filter((c) => c.id !== conv.id).slice(0, 6)" :key="pc.id"
               style="margin-bottom:6px; font-size:13px">
            <router-link :to="`/conversations/${pc.id}`" style="display:block; overflow:hidden; text-overflow:ellipsis; white-space:nowrap">
              <span class="pill" :class="`status-${pc.status}`" style="margin-right:4px">#{{ pc.number }}</span>{{ pc.subject }}
            </router-link>
          </div>
        </div>
        <div v-if="(conv.participants || []).length > 1" class="card">
          <h3>On this thread</h3>
          <div v-for="p in conv.participants" :key="p.email"
               style="display:flex; gap:8px; align-items:center; margin-bottom:6px">
            <span class="avatar small" :style="{ background: avatarColor(p.email) }">{{ initials(p.name || p.email) }}</span>
            <span style="min-width:0; font-size:13px; overflow-wrap:anywhere">{{ p.name || p.email }}</span>
          </div>
        </div>
        </div>
      </aside>
    </div>
  </section>
</template>
