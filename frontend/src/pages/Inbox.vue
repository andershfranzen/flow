<script setup>
import { ref, computed, watch, onMounted, onUnmounted, TransitionGroup } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useSession } from '../stores/session'
import { useInbox } from '../stores/inbox'
import { openStream } from '../sse'
import { api } from '../api'
import { t } from '../strings'
import ThreadPane from '../components/ThreadPane.vue'
import NewConversationModal from '../components/NewConversationModal.vue'
import { avatarColor, initials } from '../avatar'
import { shortTime } from '../format'

const props = defineProps({ id: String })
const route = useRoute()
const router = useRouter()
const session = useSession()
const inbox = useInbox()

const FOLDERS = ['unassigned', 'mine', 'assigned', 'starred', 'snoozed', 'closed', 'spam', 'trash']
const searchInput = ref('')
const selected = ref(new Set())
const agents = ref([])
const tags = ref([])
const showNew = ref(false)
let stream = null

const currentId = computed(() => (props.id ? Number(props.id) : null))

function restream() {
  stream?.close()
  stream = openStream(currentId.value, {
    onConversations: () => { inbox.loadConversations(); inbox.refreshUnread() },
    onPresence: ({ viewers }) => { inbox.viewers = viewers },
  })
}

function onKeydown(e) {
  if (e.metaKey || e.ctrlKey || e.altKey) return
  const tag = e.target.tagName
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || e.target.isContentEditable) return
  const list = inbox.conversations
  const idx = list.findIndex((c) => c.id === currentId.value)
  if (e.key === 'j' || e.key === 'k') {
    const next = list[e.key === 'j' ? Math.min(idx + 1, list.length - 1) : Math.max(idx - 1, 0)]
    if (next) router.push(`/conversations/${next.id}`)
    e.preventDefault()
  } else if (e.key === 'e' && currentId.value) {
    inbox.update(currentId.value, { status: 'closed' })
    e.preventDefault()
  } else if (e.key === 'r' && currentId.value) {
    document.querySelector('.composer .editor')?.focus()
    e.preventDefault()
  }
}

function toggleSelect(id, e) {
  e.stopPropagation()
  const next = new Set(selected.value)
  next.has(id) ? next.delete(id) : next.add(id)
  selected.value = next
}

async function bulk(attrs) {
  await api.patch('/api/conversations/bulk', { ids: [...selected.value], ...attrs })
  selected.value = new Set()
  await inbox.loadConversations()
}

function bulkAssign(e) {
  const id = e.target.value
  e.target.value = ''
  if (id !== '') bulk({ assignee_id: id === 'none' ? '' : id })
}

function toggleSort() {
  inbox.sort = inbox.sort === 'oldest' ? 'newest' : 'oldest'
  inbox.loadConversations()
}

function setFilter() { inbox.loadConversations() }

onMounted(async () => {
  window.addEventListener('keydown', onKeydown)
  api.get('/api/agents').then((a) => (agents.value = a))
  api.get('/api/tags').then((x) => (tags.value = x))
  await inbox.loadMailboxes()
  await inbox.loadConversations()
  inbox.refreshUnread()
  if (currentId.value) inbox.open(currentId.value)
  restream()
})
onUnmounted(() => { stream?.close(); window.removeEventListener('keydown', onKeydown) })

watch(currentId, (id) => {
  if (id) inbox.open(id)
  else inbox.current = null
  restream()
})

function selectFolder(folder) {
  inbox.folder = folder
  inbox.query = ''
  searchInput.value = ''
  selected.value = new Set()
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

function openNewConversation() { showNew.value = true }

async function onConversationCreated(conv) {
  showNew.value = false
  await inbox.loadConversations()
  router.push(`/conversations/${conv.id}`)
}

async function logout() {
  await session.logout()
  router.push('/login')
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
        <div class="me" :title="session.agent?.email">{{ session.agent?.name }}</div>
        <div style="display:flex; gap:8px; align-items:center">
          <router-link to="/settings">{{ t.settings }}</router-link>
          <span v-if="inbox.unread" class="pill">{{ inbox.unread }}</span>
          <button class="ghost" style="margin-left:auto; padding:4px 10px" @click="logout">{{ t.logout }}</button>
        </div>
      </div>
    </aside>

    <section class="list-col" aria-label="Conversations">
      <div class="list-head">
        <input v-model="searchInput" type="search" :placeholder="t.search"
               @keydown.enter="search" aria-label="Search conversations" />
        <button class="ghost" @click="toggleSort"
                :title="inbox.sort === 'oldest' ? 'Oldest first (queue mode)' : 'Newest first'">
          {{ inbox.sort === 'oldest' ? '↑' : '↓' }}
        </button>
        <button class="primary" @click="openNewConversation" title="New conversation">＋</button>
      </div>
      <div class="filter-row">
        <select v-model="inbox.assigneeFilter" @change="setFilter" aria-label="Filter by assignee">
          <option value="">Anyone</option>
          <option v-for="a in agents" :key="a.id" :value="a.id">{{ a.name }}</option>
        </select>
        <select v-if="tags.length" v-model="inbox.tagFilter" @change="setFilter" aria-label="Filter by tag">
          <option value="">Any tag</option>
          <option v-for="x in tags" :key="x.id" :value="x.name">{{ x.name }}</option>
        </select>
      </div>
      <div v-if="selected.size" class="bulk-bar">
        <strong>{{ selected.size }}</strong>
        <button class="ghost" @click="bulk({ status: 'closed' })">Close</button>
        <button class="ghost" @click="bulk({ status: 'spam' })">Spam</button>
        <button class="ghost" @click="bulk({ status: 'trash' })">Trash</button>
        <select @change="bulkAssign" aria-label="Assign selected">
          <option value="">Assign…</option>
          <option value="none">Unassign</option>
          <option v-for="a in agents" :key="a.id" :value="a.id">{{ a.name }}</option>
        </select>
        <button class="ghost" @click="selected = new Set()">✕</button>
      </div>
      <TransitionGroup tag="ul" name="list" class="conv-list">
        <li v-for="c in inbox.conversations" :key="c.id">
          <button class="conv-item" :class="{ active: c.id === currentId, unread: c.unread, selecting: selected.size }"
                  @click="router.push(`/conversations/${c.id}`)">
            <span class="select-box" @click="toggleSelect(c.id, $event)">
              <input type="checkbox" :checked="selected.has(c.id)" tabindex="-1" aria-label="Select conversation" />
            </span>
            <span class="avatar" :style="{ background: avatarColor(c.customer.email) }">
              {{ initials(c.customer.name || c.customer.email) }}
            </span>
            <span class="conv-main">
              <span class="row1">
                <span class="who">{{ c.customer.name || c.customer.email }}</span>
                <span class="when">{{ shortTime(c.last_message_at) }}</span>
              </span>
              <span class="line2">
                <span v-if="c.starred" class="star">★ </span><span class="subj">{{ c.subject || '(no subject)' }}</span><span class="prev"> — {{ c.preview }}</span>
              </span>
              <span v-if="c.assignee || c.tags.length || c.status === 'pending'" class="meta">
                <span v-if="c.status === 'pending'" class="pill status-pending">{{ t.statuses.pending }}</span>
                <span v-if="c.assignee" class="pill">{{ c.assignee.name }}</span>
                <span v-for="tag in c.tags" :key="tag.id" class="tag-pill" :style="{ background: tag.color }">{{ tag.name }}</span>
              </span>
            </span>
          </button>
        </li>
        <li v-if="!inbox.conversations.length && !inbox.loading" key="__empty" class="empty">{{ t.noConversations }}</li>
      </TransitionGroup>
    </section>

    <ThreadPane v-if="currentId" :key="currentId" />
    <section v-else class="pane">
      <div class="empty" style="margin-top:20vh">Select a conversation</div>
    </section>

    <Transition name="fade">
      <NewConversationModal v-if="showNew" :mailboxes="inbox.mailboxes"
                            :default-mailbox-id="inbox.mailboxId"
                            @close="showNew = false" @created="onConversationCreated" />
    </Transition>
  </div>
</template>
