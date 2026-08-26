<script setup>
import { ref, computed, watch, onMounted, onUnmounted, nextTick, TransitionGroup } from 'vue'
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
import { Bell, Plus, X, Pencil, Star, Check, ArrowUp, ArrowDown, TriangleAlert, Settings as SettingsIcon, LogOut } from 'lucide-vue-next'
import StyledSelect from '../components/StyledSelect.vue'

const props = defineProps({ id: String })
const route = useRoute()
const router = useRouter()
const session = useSession()
const inbox = useInbox()

const FOLDERS = ['unassigned', 'mine', 'assigned', 'starred', 'snoozed', 'closed', 'spam', 'trash']
const searchInput = ref('')
const selected = ref(new Set())
const dragging = ref(null) // conversation id mid-drag
const dragOverFolder = ref(null)
// Drop targets: triage folders minus the one you're already in — dragging
// from Mine offers Unassigned (to unassign), and vice versa.
const DROP_FOLDERS = computed(() =>
  ['unassigned', 'mine', 'spam', 'trash'].filter((f) => f !== inbox.folder)
)
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
  } else if (e.key === 'Escape' && showNotifs.value) {
    showNotifs.value = false
  } else if (e.key === 'r' && currentId.value) {
    document.querySelector('.composer .editor')?.focus()
    e.preventDefault()
  }
}

// Allowing a "drop" anywhere suppresses the browser's slow snap-back
// animation, so dragend (and the fold-out) fires instantly on release.
function allowDropEverywhere(e) { e.preventDefault() }

function onDragStart(c, e) {
  dragging.value = c.id
  e.dataTransfer.effectAllowed = 'move'
  e.dataTransfer.setData('text/plain', String(c.id))
  document.addEventListener('dragover', allowDropEverywhere)
  document.addEventListener('drop', allowDropEverywhere)
}

function onDragEnd() {
  dragging.value = null
  dragOverFolder.value = null
  document.removeEventListener('dragover', allowDropEverywhere)
  document.removeEventListener('drop', allowDropEverywhere)
}

function onDropFolder(folder) {
  if (!dragging.value || !DROP_FOLDERS.value.includes(folder)) return
  const ids = selected.value.has(dragging.value) && selected.value.size > 1
    ? [...selected.value] : [dragging.value]
  const attrs = folder === 'mine' ? { assignee_id: session.agent.id }
    : folder === 'unassigned' ? { assignee_id: '' }
    : { status: folder }
  if (inbox.personalFolderId) attrs.remove_from_folder_id = inbox.personalFolderId
  onDragEnd()
  removeRowsLocally(ids)
  selected.value = new Set()
  if (inbox.folderCounts[folder] != null) inbox.folderCounts[folder] += ids.length
  backgroundPatch({ ids, ...attrs })
}

function toggleSelect(id, e) {
  e.stopPropagation()
  const next = new Set(selected.value)
  next.has(id) ? next.delete(id) : next.add(id)
  selected.value = next
}

// Optimistic: rows leave the view the instant you act; the server call runs
// behind it and a failure falls back to a full reload.
function removeRowsLocally(ids) {
  const gone = new Set(ids)
  inbox.conversations = inbox.conversations.filter((c) => !gone.has(c.id))
}

function backgroundPatch(payload) {
  api.patch('/api/conversations/bulk', payload)
    .then(() => { inbox.loadConversations(); if (payload.remove_from_folder_id) inbox.loadPersonalFolders() })
    .catch(() => { inbox.loadConversations(); if (payload.remove_from_folder_id) inbox.loadPersonalFolders() })
}

function bulk(attrs) {
  const ids = [...selected.value]
  removeRowsLocally(ids)
  selected.value = new Set()
  backgroundPatch({ ids, ...attrs })
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
  document.addEventListener('mousedown', onGlobalPointer)
  api.get('/api/agents').then((a) => (agents.value = a))
  api.get('/api/tags').then((x) => (tags.value = x))
  inbox.loadPersonalFolders()
  await inbox.loadMailboxes()
  await inbox.loadConversations()
  inbox.refreshUnread()
  if (currentId.value) inbox.open(currentId.value)
  restream()
})
onUnmounted(() => {
  stream?.close()
  window.removeEventListener('keydown', onKeydown)
  document.removeEventListener('mousedown', onGlobalPointer)
})

watch(currentId, (id) => {
  if (id) inbox.open(id)
  else inbox.current = null
  restream()
})

function selectFolder(folder) {
  inbox.folder = folder
  inbox.personalFolderId = null
  inbox.query = ''
  searchInput.value = ''
  selected.value = new Set()
  inbox.loadConversations()
  router.push('/inbox')
}

function selectPersonalFolder(id) {
  inbox.personalFolderId = id
  inbox.folder = 'all'
  inbox.query = ''
  searchInput.value = ''
  selected.value = new Set()
  inbox.loadConversations()
  router.push('/inbox')
}

const showNotifs = ref(false)
const notifs = ref([])
const NOTIF_LABELS = {
  new_unassigned: 'New conversation', assigned_to_me: 'Assigned to you',
  customer_reply: 'Customer replied', note_on_mine: 'New note', mention: 'You were mentioned',
}

const notifPanelStyle = ref({})
const showUserMenu = ref(false)

async function toggleNotifs(e) {
  showNotifs.value = !showNotifs.value
  showUserMenu.value = false
  if (!showNotifs.value) return
  const r = e.currentTarget.getBoundingClientRect()
  const railRight = document.querySelector('.rail')?.getBoundingClientRect().right ?? r.right
  // Desktop: fly out clear of the rail, bottom-aligned with the bell.
  notifPanelStyle.value = window.innerWidth > 700
    ? { left: `${Math.round(Math.max(r.right, railRight) + 10)}px`,
        bottom: `${Math.max(10, Math.round(window.innerHeight - r.bottom))}px` }
    : { left: '10px', right: '10px', top: `${Math.round(r.bottom + 8)}px` }
  const data = await api.get('/api/notifications')
  notifs.value = data.notifications
  // Opening the panel clears the badge, but the unread highlights stay
  // until the next open so you can still see what's new.
  inbox.unread = 0
  if (data.unread) api.post('/api/notifications/read')
}

function onGlobalPointer(e) {
  if (showNotifs.value && !e.target.closest?.('.notif-panel') && !e.target.closest?.('.bell')) {
    showNotifs.value = false
  }
  if (showUserMenu.value && !e.target.closest?.('.user-menu') && !e.target.closest?.('.me-button')) {
    showUserMenu.value = false
  }
}

function openNotif(n) {
  showNotifs.value = false
  router.push(`/conversations/${n.conversation.id}`)
}

const creatingFolder = ref(false)
const newFolderName = ref('')
const newFolderInput = ref(null)

function startCreateFolder() {
  creatingFolder.value = true
  newFolderName.value = ''
  nextTick(() => newFolderInput.value?.focus())
}

async function commitCreateFolder() {
  const name = newFolderName.value.trim()
  if (!name) { creatingFolder.value = false; return }
  try {
    await api.post('/api/personal_folders', { name })
    await inbox.loadPersonalFolders()
  } finally {
    creatingFolder.value = false
    newFolderName.value = ''
  }
}

function cancelCreateFolder() {
  creatingFolder.value = false
  newFolderName.value = ''
}

async function renamePersonalFolder(pf) {
  const name = window.prompt('Rename folder:', pf.name)
  if (!name?.trim() || name.trim() === pf.name) return
  await api.patch(`/api/personal_folders/${pf.id}`, { name: name.trim() })
  await inbox.loadPersonalFolders()
}

function deletePersonalFolder(pf) {
  if (!confirm(`Delete folder "${pf.name}"? Conversations stay untouched.`)) return
  inbox.personalFolders = inbox.personalFolders.filter((f) => f.id !== pf.id) // instant
  const wasViewing = inbox.personalFolderId === pf.id
  if (wasViewing) { inbox.personalFolderId = null; inbox.folder = 'unassigned' }
  api.delete(`/api/personal_folders/${pf.id}`)
    .catch(() => inbox.loadPersonalFolders())
  if (wasViewing) inbox.loadConversations()
}

function onDropPersonalFolder(pf) {
  if (!dragging.value) return
  const ids = selected.value.has(dragging.value) && selected.value.size > 1
    ? [...selected.value] : [dragging.value]
  onDragEnd()
  selected.value = new Set()
  pf.count = (pf.count || 0) + ids.length // optimistic; reconciled below
  api.post(`/api/personal_folders/${pf.id}/items`, { conversation_ids: ids })
    .then(() => { inbox.loadPersonalFolders(); inbox.loadConversations() })
    .catch(() => { inbox.loadPersonalFolders(); inbox.loadConversations() })
}

function bulkRemoveFromFolder() {
  const ids = [...selected.value]
  removeRowsLocally(ids)
  selected.value = new Set()
  api.patch('/api/conversations/bulk', { ids, remove_from_folder_id: inbox.personalFolderId })
    .then(() => inbox.loadPersonalFolders())
    .catch(() => { inbox.loadConversations(); inbox.loadPersonalFolders() })
}

function selectMailbox(id) {
  inbox.mailboxId = id
  inbox.loadConversations()
}

let searchTimer = null
function onSearchInput() {
  clearTimeout(searchTimer)
  searchTimer = setTimeout(search, 200)
}

function search() {
  clearTimeout(searchTimer)
  inbox.query = searchInput.value.trim()
  inbox.loadConversations()
}

function clearSearch() {
  searchInput.value = ''
  search()
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
    <aside class="rail" :class="{ dragging: !!dragging }">
      <div class="brand-block">
        <template v-if="session.org?.logo_url">
          <img class="company-logo" :src="session.org.logo_url" :alt="session.org.site_name || 'Company logo'" draggable="false" />
          <div class="brand by-flow">by {{ t.appName }}</div>
        </template>
        <div v-else class="brand">{{ t.appName }}</div>
      </div>
      <nav aria-label="Mailboxes">
        <div class="section">Mailboxes</div>
        <button class="rail-item" :class="{ active: inbox.mailboxId === null }" @click="selectMailbox(null)">
          <span class="label-text">All</span>
        </button>
        <button v-for="m in inbox.mailboxes" :key="m.id" class="rail-item"
                :class="{ active: inbox.mailboxId === m.id }" @click="selectMailbox(m.id)"
                :data-tip="m.address">
          <span class="label-text">{{ m.name }}</span>
          <span v-if="m.fetch_error" data-tip="Mail fetch is failing" style="color:var(--warn); display:inline-flex"><TriangleAlert :size="14" /></span>
        </button>
      </nav>
      <nav aria-label="My folders" v-if="inbox.personalFolders.length || true">
        <div class="section">{{ t.myFolders }}</div>
        <button v-for="pf in inbox.personalFolders" :key="pf.id" class="rail-item pf-item"
                :class="{ active: inbox.personalFolderId === pf.id,
                          'drop-target': dragging, 'drag-over': dragOverFolder === `pf${pf.id}` }"
                @click="selectPersonalFolder(pf.id)"
                @dragover.prevent
                @dragenter.prevent="dragging && (dragOverFolder = `pf${pf.id}`)"
                @dragleave="dragOverFolder === `pf${pf.id}` && (dragOverFolder = null)"
                @drop.prevent="onDropPersonalFolder(pf)">
          <span class="label-text"><span class="pf-dot" :style="{ background: pf.color }"></span>{{ pf.name }}</span>
          <span class="pf-actions">
            <span class="pf-act" :data-tip="`Rename`" @click.stop="renamePersonalFolder(pf)"><Pencil :size="11" /></span>
            <span class="pf-act" :data-tip="`Delete folder`" @click.stop="deletePersonalFolder(pf)"><X :size="11" /></span>
          </span>
          <span class="count">{{ pf.count || '' }}</span>
        </button>
        <div v-if="creatingFolder" class="pf-create">
          <input ref="newFolderInput" v-model="newFolderName" :placeholder="t.newFolder"
                 maxlength="40" @keydown.enter.prevent="commitCreateFolder"
                 @keydown.esc="cancelCreateFolder" @blur="commitCreateFolder" />
        </div>
        <button v-else class="rail-item pf-new" :class="{ 'drop-hidden': dragging }" @click="startCreateFolder">
          <span class="label-text" style="color:var(--muted); display:inline-flex; align-items:center; gap:5px"><Plus :size="14" /> {{ t.newFolder }}</span>
        </button>
      </nav>
      <nav aria-label="Folders">
        <div class="section">Folders</div>
        <button v-for="f in FOLDERS" :key="f" class="rail-item"
                :class="{
                  active: inbox.folder === f && !inbox.query,
                  'drop-hidden': dragging && !DROP_FOLDERS.includes(f),
                  'drop-target': dragging && DROP_FOLDERS.includes(f),
                  'drag-over': dragOverFolder === f,
                }"
                @click="selectFolder(f)"
                @dragover.prevent
                @dragenter.prevent="dragging && DROP_FOLDERS.includes(f) && (dragOverFolder = f)"
                @dragleave="dragOverFolder === f && (dragOverFolder = null)"
                @drop.prevent="onDropFolder(f)">
          <span class="label-text">{{ t.folders[f] }}</span>
          <span class="count">{{ inbox.folderCounts[f] || '' }}</span>
        </button>
      </nav>
      <div class="foot">
        <Transition name="fade">
          <div v-if="showUserMenu" class="user-menu card">
            <router-link to="/settings" class="user-menu-item" @click="showUserMenu = false">
              <SettingsIcon :size="15" /> {{ t.settings }}
            </router-link>
            <button class="user-menu-item" @click="logout">
              <LogOut :size="15" /> {{ t.logout }}
            </button>
          </div>
        </Transition>
        <div class="foot-row">
          <button class="me-button" :aria-expanded="showUserMenu" :data-tip="session.agent?.email"
                  @click="showUserMenu = !showUserMenu; showNotifs = false">
            <span class="avatar small" :style="{ background: avatarColor(session.agent?.email || '') }">
              {{ initials(session.agent?.name || '?') }}
            </span>
            <span class="me-name">{{ session.agent?.name }}</span>
          </button>
          <button class="ghost bell" data-tip="Notifications" :aria-expanded="showNotifs" @click="toggleNotifs">
            <Bell :size="17" />
            <span v-if="inbox.unread" class="bell-badge">{{ inbox.unread > 99 ? '99+' : inbox.unread }}</span>
          </button>
        </div>
      </div>

      <Teleport to="body">
        <Transition name="fade">
          <div v-if="showNotifs" class="notif-panel card" :style="notifPanelStyle">
            <div class="insights-head" style="margin-bottom:6px">
              <span>Notifications</span>
            </div>
            <button v-for="n in notifs" :key="n.id" class="notif-item" :class="{ unread: !n.read_at }"
                    @click="openNotif(n)">
              <span class="notif-kind">{{ NOTIF_LABELS[n.kind] || n.kind }} · {{ shortTime(n.created_at, session.agent) }}</span>
              <span class="notif-subject"><span class="notif-num">#{{ n.conversation.number }}</span>{{ n.conversation.subject || '(no subject)' }}</span>
            </button>
            <div v-if="!notifs.length" class="empty" style="padding:16px">Nothing yet</div>
          </div>
        </Transition>
      </Teleport>
    </aside>

    <section class="list-col" aria-label="Conversations">
      <div class="list-head">
        <input v-model="searchInput" type="search" :placeholder="t.search"
               @input="onSearchInput" @keydown.enter="search" @keydown.esc="clearSearch"
               aria-label="Search conversations" />
        <button class="ghost" @click="toggleSort"
                :data-tip="inbox.sort === 'oldest' ? 'Oldest first (queue mode)' : 'Newest first'">
          <ArrowUp v-if="inbox.sort === 'oldest'" :size="15" /><ArrowDown v-else :size="15" />
        </button>
        <button class="primary" @click="openNewConversation" data-tip="New conversation"><Plus :size="17" /></button>
      </div>
      <div class="filter-row">
        <StyledSelect v-model="inbox.assigneeFilter" aria-label="Filter by assignee" @change="setFilter"
                      :options="[{ value: '', label: 'Anyone' }, ...agents.map((a) => ({ value: a.id, label: a.name }))]" />
        <StyledSelect v-if="tags.length" v-model="inbox.tagFilter" aria-label="Filter by tag" @change="setFilter"
                      :options="[{ value: '', label: 'Any tag' }, ...tags.map((x) => ({ value: x.name, label: x.name }))]" />
      </div>
      <Transition name="bulkbar">
        <div v-if="selected.size" class="bulk-bar">
          <div class="bulk-row">
            <strong>{{ selected.size }} selected</strong>
            <span style="flex:1"></span>
            <button class="ghost" data-tip="Clear selection" @click="selected = new Set()"><X :size="14" /></button>
          </div>
          <div class="bulk-row">
            <button v-if="inbox.personalFolderId" @click="bulkRemoveFromFolder">Remove from folder</button>
            <button @click="bulk({ status: 'closed' })">Close</button>
            <button @click="bulk({ status: 'spam' })">Spam</button>
            <button @click="bulk({ status: 'trash' })">Trash</button>
            <StyledSelect :model-value="''" placeholder="Assign…" aria-label="Assign selected" style="flex:1; min-width:0"
                          @change="(v) => bulkAssign({ target: { value: v } })"
                          :options="[{ value: 'none', label: 'Unassign' }, ...agents.map((a) => ({ value: a.id, label: a.name }))]" />
          </div>
        </div>
      </Transition>
      <TransitionGroup tag="ul" name="list" class="conv-list">
        <li v-for="c in inbox.conversations" :key="c.id">
          <button class="conv-item" :class="{ active: c.id === currentId, unread: c.unread, selecting: selected.size, selected: selected.has(c.id), 'being-dragged': dragging === c.id }"
                  draggable="true" @dragstart="onDragStart(c, $event)" @dragend="onDragEnd"
                  @click="router.push(`/conversations/${c.id}`)">
            <span class="avatar-select" @click="toggleSelect(c.id, $event)">
              <span class="avatar" :style="{ background: avatarColor(c.customer.email) }">
                {{ initials(c.customer.name || c.customer.email) }}
              </span>
              <span class="select-overlay" :class="{ checked: selected.has(c.id) }"
                    role="checkbox" :aria-checked="selected.has(c.id)" aria-label="Select conversation"><Check :size="18" /></span>
            </span>
            <span class="conv-main">
              <span class="row1">
                <span class="who">{{ c.customer.name || c.customer.email }}</span>
                <span class="when">{{ shortTime(c.last_message_at, session.agent) }}</span>
              </span>
              <span class="line2">
                <Star v-if="c.starred" :size="12" class="star" fill="currentColor" /><span class="subj">{{ c.subject || '(no subject)' }}</span><span class="prev"> — {{ c.preview }}</span>
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
