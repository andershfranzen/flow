<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useSession } from '../stores/session'
import { useInbox } from '../stores/inbox'
import { openStream } from '../sse'
import { api } from '../api'
import { t } from '../strings'
import ThreadPane from '../components/ThreadPane.vue'
import { avatarColor, initials } from '../avatar'

const props = defineProps({ id: String })
const route = useRoute()
const router = useRouter()
const session = useSession()
const inbox = useInbox()

const FOLDERS = ['unassigned', 'mine', 'assigned', 'starred', 'closed', 'spam', 'trash']
const searchInput = ref('')
const showNew = ref(false)
const newConv = ref({ mailbox_id: null, to: '', subject: '', body_text: '' })
let stream = null

const currentId = computed(() => (props.id ? Number(props.id) : null))

function restream() {
  stream?.close()
  stream = openStream(currentId.value, {
    onConversations: () => { inbox.loadConversations(); inbox.refreshUnread() },
    onPresence: ({ viewers }) => { inbox.viewers = viewers },
  })
}

onMounted(async () => {
  await inbox.loadMailboxes()
  await inbox.loadConversations()
  inbox.refreshUnread()
  if (currentId.value) inbox.open(currentId.value)
  restream()
})
onUnmounted(() => stream?.close())

watch(currentId, (id) => {
  if (id) inbox.open(id)
  else inbox.current = null
  restream()
})

function selectFolder(folder) {
  inbox.folder = folder
  inbox.query = ''
  searchInput.value = ''
  inbox.loadConversations()
  router.push('/inbox')
}

function selectMailbox(id) {
  inbox.mailboxId = id
  inbox.loadConversations()
}

function search() {
  inbox.query = searchInput.value
  inbox.loadConversations()
}

async function createConversation() {
  const payload = {
    mailbox_id: newConv.value.mailbox_id || inbox.mailboxes[0]?.id,
    to: newConv.value.to.split(/[,;\s]+/).filter(Boolean),
    subject: newConv.value.subject,
    body_text: newConv.value.body_text,
  }
  const conv = await api.post('/api/conversations', payload)
  showNew.value = false
  newConv.value = { mailbox_id: null, to: '', subject: '', body_text: '' }
  await inbox.loadConversations()
  router.push(`/conversations/${conv.id}`)
}

async function logout() {
  await session.logout()
  router.push('/login')
}

function timeAgo(iso) {
  if (!iso) return ''
  const s = (Date.now() - new Date(iso)) / 1000
  if (s < 60) return 'now'
  if (s < 3600) return `${Math.floor(s / 60)}m`
  if (s < 86400) return `${Math.floor(s / 3600)}h`
  return `${Math.floor(s / 86400)}d`
}
</script>

<template>
  <div class="shell" :class="{ 'viewing-conversation': !!currentId }">
    <aside class="rail">
      <div class="brand">{{ t.appName }}</div>
      <nav aria-label="Mailboxes">
        <div class="section">Mailboxes</div>
        <button class="rail-item" :class="{ active: inbox.mailboxId === null }" @click="selectMailbox(null)">
          <span class="label-text">All</span>
        </button>
        <button v-for="m in inbox.mailboxes" :key="m.id" class="rail-item"
                :class="{ active: inbox.mailboxId === m.id }" @click="selectMailbox(m.id)"
                :title="m.address">
          <span class="label-text">{{ m.name }}</span>
          <span v-if="m.fetch_error" title="Fetch failing">⚠️</span>
        </button>
      </nav>
      <nav aria-label="Folders">
        <div class="section">Folders</div>
        <button v-for="f in FOLDERS" :key="f" class="rail-item"
                :class="{ active: inbox.folder === f && !inbox.query }" @click="selectFolder(f)">
          <span class="label-text">{{ t.folders[f] }}</span>
          <span class="count">{{ inbox.folderCounts[f] || '' }}</span>
        </button>
      </nav>
      <div class="foot">
        <div style="margin-bottom:6px">
          <router-link to="/settings">{{ t.settings }}</router-link>
          <span v-if="inbox.unread" class="pill" style="margin-left:6px">{{ inbox.unread }}</span>
        </div>
        <button class="ghost" @click="logout">{{ t.logout }} ({{ session.agent?.name }})</button>
      </div>
    </aside>

    <section class="list-col" aria-label="Conversations">
      <div class="list-head">
        <input v-model="searchInput" type="search" :placeholder="t.search"
               @keydown.enter="search" aria-label="Search conversations" />
        <button class="primary" @click="showNew = true" title="New conversation">＋</button>
      </div>
      <ul class="conv-list">
        <li v-for="c in inbox.conversations" :key="c.id">
          <button class="conv-item" :class="{ active: c.id === currentId }"
                  @click="router.push(`/conversations/${c.id}`)">
            <span class="avatar" :style="{ background: avatarColor(c.customer.email) }">
              {{ initials(c.customer.name || c.customer.email) }}
            </span>
            <span class="conv-main">
              <span class="row1">
                <span class="who">{{ c.customer.name || c.customer.email }}</span>
                <span class="when">{{ timeAgo(c.last_message_at) }}</span>
              </span>
              <span class="subject"><span v-if="c.starred" class="star">★</span> <span class="num">#{{ c.number }}</span>{{ c.subject || '(no subject)' }}</span>
              <span class="preview">{{ c.preview }}</span>
              <span class="meta">
                <span class="pill" :class="`status-${c.status}`">{{ t.statuses[c.status] }}</span>
                <span v-if="c.assignee" class="pill">{{ c.assignee.name }}</span>
                <span v-for="tag in c.tags" :key="tag.id" class="tag-pill" :style="{ background: tag.color }">{{ tag.name }}</span>
              </span>
            </span>
          </button>
        </li>
        <li v-if="!inbox.conversations.length && !inbox.loading" class="empty">{{ t.noConversations }}</li>
      </ul>
    </section>

    <ThreadPane v-if="currentId" :key="currentId" />
    <section v-else class="pane">
      <div class="empty" style="margin-top:20vh">Select a conversation</div>
    </section>

    <div v-if="showNew" class="modal-backdrop" @click.self="showNew = false">
      <form class="modal" @submit.prevent="createConversation">
        <h2>{{ t.newConversation }}</h2>
        <div style="display:flex; flex-direction:column; gap:10px">
          <div>
            <label>Mailbox</label>
            <select v-model="newConv.mailbox_id" style="width:100%">
              <option v-for="m in inbox.mailboxes" :key="m.id" :value="m.id">{{ m.name }} ({{ m.address }})</option>
            </select>
          </div>
          <div>
            <label>{{ t.to }}</label>
            <input v-model="newConv.to" required placeholder="customer@example.com" style="width:100%" />
          </div>
          <div>
            <label>{{ t.subject }}</label>
            <input v-model="newConv.subject" required style="width:100%" />
          </div>
          <div>
            <label>Message</label>
            <textarea v-model="newConv.body_text" required rows="6" style="width:100%"></textarea>
          </div>
          <div style="display:flex; gap:8px; justify-content:flex-end">
            <button type="button" @click="showNew = false">{{ t.cancel }}</button>
            <button class="primary">{{ t.send }}</button>
          </div>
        </div>
      </form>
    </div>
  </div>
</template>
