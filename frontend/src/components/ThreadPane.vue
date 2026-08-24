<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { useSession } from '../stores/session'
import { useInbox } from '../stores/inbox'
import { api } from '../api'
import { t } from '../strings'
import Composer from './Composer.vue'

const router = useRouter()
const session = useSession()
const inbox = useInbox()

const agents = ref([])
const tags = ref([])
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
function toggleTag(tag) {
  const ids = conv.value.tags.map((x) => x.id)
  const next = ids.includes(tag.id) ? ids.filter((x) => x !== tag.id) : [...ids, tag.id]
  inbox.update(conv.value.id, { tag_ids: next })
}
async function onSent() {
  await inbox.open(conv.value.id)
  await inbox.loadConversations()
}

// Inline images: rewrite cid: to attachment URLs (A20 display side).
function renderHtml(m) {
  let html = m.body_html || ''
  for (const a of m.attachments || []) {
    if (a.content_id) html = html.replaceAll(`cid:${a.content_id}`, a.url)
  }
  return html
}

function fmt(iso) { return new Date(iso).toLocaleString() }
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
      <button class="ghost" @click="router.push('/inbox')" title="Back">←</button>
      <h2>
        <span class="number">#{{ conv.number }}</span>
        {{ conv.subject || '(no subject)' }}
      </h2>
      <button class="ghost" @click="toggleStar" :title="conv.starred ? 'Unstar' : 'Star'">
        {{ conv.starred ? '★' : '☆' }}
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
        <div class="card" style="position:absolute; z-index:5; margin-top:4px">
          <label v-for="tag in tags" :key="tag.id" style="display:flex; gap:6px; align-items:center; color:var(--text)">
            <input type="checkbox" :checked="conv.tags.some((x) => x.id === tag.id)" @change="toggleTag(tag)" />
            <span class="tag-pill" :style="{ background: tag.color }">{{ tag.name }}</span>
          </label>
          <span v-if="!tags.length" class="hint" style="font-size:12px; color:var(--muted)">No tags yet — create them in Settings</span>
        </div>
      </details>
    </header>

    <div v-if="inbox.viewers.length" class="collision" style="margin:10px 16px 0">
      👀 {{ inbox.viewers.map((v) => v.name).join(', ') }} {{ t.viewing }}
    </div>

    <div class="pane-body" ref="transcriptEl">
      <div class="transcript">
        <template v-for="item in timeline" :key="item._type + item.id">
          <div v-if="item._type === 'event'" class="event-line">{{ eventText(item) }} · {{ fmt(item.created_at) }}</div>
          <article v-else class="msg" :class="item.kind">
            <div class="msg-head">
              <span>
                <span class="from">{{ item.kind === 'inbound' ? (item.from_name || item.from_email) : (item.agent?.name || 'Agent') }}</span>
                <span v-if="item.kind === 'note'"> · {{ t.internalNote }}</span>
                <span v-else-if="item.kind === 'outbound'"> → {{ (item.to || []).join(', ') }}</span>
              </span>
              <span>
                <span v-if="item.bounce" class="pill bounce">{{ t.bounced }}</span>
                <span v-if="item.status === 'queued'" class="pill">{{ t.queued }}</span>
                <span v-if="item.status === 'failed'" class="pill bounce">{{ t.failed }}</span>
                {{ fmt(item.created_at) }}
              </span>
            </div>
            <div v-if="item.body_html" class="msg-body" v-html="renderHtml(item)"></div>
            <div v-else class="msg-body" style="white-space:pre-wrap">{{ item.body_text }}</div>
            <div v-if="(item.attachments || []).some((a) => !a.content_id)" class="attachments">
              <a v-for="a in item.attachments.filter((a) => !a.content_id)" :key="a.id"
                 class="attachment" :href="a.url" target="_blank" rel="noopener">
                📎 {{ a.filename }} ({{ Math.round(a.byte_size / 1024) }} KB)
              </a>
            </div>
          </article>
        </template>

        <Composer :conversation="conv" @sent="onSent" />
      </div>

      <aside class="side-panel">
        <div class="card">
          <h3>Customer</h3>
          <div>{{ conv.customer.name || '—' }}</div>
          <div style="color:var(--muted); font-size:13px">{{ conv.customer.email }}</div>
        </div>
      </aside>
    </div>
  </section>
</template>
