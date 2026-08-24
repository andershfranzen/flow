<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { api } from '../api'
import { t } from '../strings'

const props = defineProps({
  conversation: { type: Object, required: true },
  forwardSeed: { type: Object, default: null },
})
const emit = defineEmits(['sent'])

const mode = ref('reply') // reply | note
const editorEl = ref(null)
const to = ref('')
const cc = ref('')
const subject = ref(null) // non-null = forward mode (B16)
const files = ref([])
const inlineImages = ref([]) // { cid, file }
const savedReplies = ref([])
const busy = ref(false)
const draftState = ref('')
let draftTimer = null
let savedDraftBody = ''

const isNote = computed(() => mode.value === 'note')

function escapeHtml(text) {
  const div = document.createElement('div')
  div.textContent = text
  return div.innerHTML
}

function editorHasContent() {
  const el = editorEl.value
  return el && (el.innerText.trim() !== '' || el.querySelector('img'))
}

// Reply-all prefill (B7): everyone from the last inbound, never our mailbox.
watch(() => props.conversation.reply_all, (ra) => {
  if (!ra) return
  to.value = ra.to.join(', ')
  cc.value = ra.cc.join(', ')
}, { immediate: true })

watch(() => props.forwardSeed, (seed) => {
  if (!seed || !editorEl.value) return
  mode.value = 'reply'
  subject.value = seed.subject
  to.value = ''
  editorEl.value.innerHTML = escapeHtml(seed.body).replace(/\n/g, '<br>')
  editorEl.value.focus()
})

function cancelForward() {
  subject.value = null
  const ra = props.conversation.reply_all
  to.value = ra ? ra.to.join(', ') : props.conversation.customer.email
  editorEl.value.innerHTML = ''
}

onMounted(async () => {
  savedReplies.value = await api.get('/api/saved_replies')
  const drafts = await api.get('/api/drafts')
  const draft = drafts.find((d) => d.conversation_id === props.conversation.id)
  if (draft?.body && editorEl.value) {
    editorEl.value.innerHTML = draft.body // agent's own draft html
    savedDraftBody = draft.body
  }
})
onUnmounted(() => clearTimeout(draftTimer))

// Autosave draft, last-write-wins (B8).
function onInput() {
  if (isNote.value) return
  clearTimeout(draftTimer)
  draftTimer = setTimeout(async () => {
    const html = editorEl.value?.innerHTML || ''
    if (html === savedDraftBody) return
    await api.put('/api/drafts', {
      conversation_id: props.conversation.id,
      mailbox_id: props.conversation.mailbox_id,
      body: html,
      to: to.value.split(/[,;\s]+/).filter(Boolean),
      cc: cc.value.split(/[,;\s]+/).filter(Boolean),
    })
    savedDraftBody = html
    draftState.value = t.draftSaved
    setTimeout(() => (draftState.value = ''), 2000)
  }, 1500)
}

function exec(command, arg = null) {
  editorEl.value?.focus()
  document.execCommand(command, false, arg)
  onInput()
}

function addLink() {
  const url = window.prompt('Link URL:', 'https://')
  if (url) exec('createLink', url)
}

function onPaste(e) {
  const images = [...(e.clipboardData?.items || [])].filter((i) => i.type.startsWith('image/'))
  if (!images.length) return
  e.preventDefault()
  for (const item of images) {
    const blob = item.getAsFile()
    if (!blob) continue
    const cid = `local-${Math.random().toString(36).slice(2, 10)}`
    inlineImages.value.push({ cid, file: new File([blob], cid, { type: blob.type }) })
    const img = document.createElement('img')
    img.src = URL.createObjectURL(blob)
    img.setAttribute('data-local-cid', cid)
    const selection = window.getSelection()
    if (selection?.rangeCount && editorEl.value.contains(selection.anchorNode)) {
      selection.getRangeAt(0).insertNode(img)
      selection.collapseToEnd()
    } else {
      editorEl.value.appendChild(img)
    }
    onInput()
  }
}

function pickFiles(e) { files.value = [...files.value, ...e.target.files] }

function outgoingHtml() {
  const clone = editorEl.value.cloneNode(true)
  clone.querySelectorAll('img[data-local-cid]').forEach((img) => {
    img.src = `cid:${img.getAttribute('data-local-cid')}`
    img.removeAttribute('data-local-cid')
  })
  return clone.innerHTML
}

async function submit(close = false) {
  if (!editorHasContent()) return
  busy.value = true
  try {
    const form = new FormData()
    form.set('kind', isNote.value ? 'note' : 'outbound')
    form.set('body_text', editorEl.value.innerText.trim())
    form.set('body_html', outgoingHtml())
    if (!isNote.value) {
      to.value.split(/[,;\s]+/).filter(Boolean).forEach((x) => form.append('to[]', x))
      cc.value.split(/[,;\s]+/).filter(Boolean).forEach((x) => form.append('cc[]', x))
      if (subject.value) form.set('subject', subject.value)
      if (close) form.set('close', 'true')
      files.value.forEach((f) => form.append('files[]', f))
      inlineImages.value.forEach(({ file }) => form.append('inline_images[]', file))
    }
    await api.post(`/api/conversations/${props.conversation.id}/messages`, form)
    editorEl.value.innerHTML = ''
    savedDraftBody = ''
    files.value = []
    inlineImages.value = []
    subject.value = null
    const ra = props.conversation.reply_all
    to.value = ra ? ra.to.join(', ') : props.conversation.customer.email
    cc.value = ra ? ra.cc.join(', ') : ''
    emit('sent')
  } finally {
    busy.value = false
  }
}

async function insertSavedReply(e) {
  const id = e.target.value
  e.target.value = ''
  if (!id) return
  const data = await api.get(`/api/saved_replies/${id}/render?conversation_id=${props.conversation.id}`)
  editorEl.value.innerHTML += (editorEl.value.innerText.trim() ? '<br>' : '') +
    escapeHtml(data.body).replace(/\n/g, '<br>')
  onInput()
}
</script>

<template>
  <form class="composer" @submit.prevent="submit(false)">
    <div class="tabs" role="tablist">
      <button type="button" role="tab" :aria-selected="!isNote" :class="{ active: !isNote }" @click="mode = 'reply'">{{ t.reply }}</button>
      <button type="button" role="tab" :aria-selected="isNote" class="note-tab" :class="{ active: isNote }" @click="mode = 'note'">{{ t.note }}</button>
      <span class="spacer"></span>
      <span class="fmt-bar">
        <button type="button" class="ghost fmt" title="Bold" @mousedown.prevent="exec('bold')"><b>B</b></button>
        <button type="button" class="ghost fmt" title="Italic" @mousedown.prevent="exec('italic')"><i>I</i></button>
        <button type="button" class="ghost fmt" title="Bullet list" @mousedown.prevent="exec('insertUnorderedList')">≡</button>
        <button type="button" class="ghost fmt" title="Link" @mousedown.prevent="addLink">🔗</button>
      </span>
    </div>
    <div v-if="!isNote" class="fields">
      <div v-if="subject !== null" class="field-row">
        <label style="margin:0; width:28px">Fwd</label>
        <input v-model="subject" aria-label="Subject" />
        <button type="button" class="ghost" @click="cancelForward" title="Cancel forward">✕</button>
      </div>
      <div class="field-row">
        <label style="margin:0; width:28px">{{ t.to }}</label>
        <input v-model="to" aria-label="To" :placeholder="subject !== null ? 'forward to…' : ''" />
      </div>
      <div class="field-row">
        <label style="margin:0; width:28px">{{ t.cc }}</label>
        <input v-model="cc" aria-label="Cc" />
      </div>
    </div>
    <div ref="editorEl" class="editor" contenteditable="true" role="textbox" aria-multiline="true"
         :aria-label="isNote ? t.note : t.reply"
         :data-placeholder="isNote ? `${t.internalNote} — @name notifies` : `${t.reply}…`"
         @input="onInput" @paste="onPaste"></div>
    <div class="actions">
      <template v-if="isNote">
        <button type="button" class="primary" :disabled="busy" @click="submit(false)">{{ t.saveNote }}</button>
      </template>
      <template v-else>
        <button type="submit" class="primary" :disabled="busy">{{ t.send }}</button>
        <button type="button" :disabled="busy" @click="submit(true)">{{ t.sendAndClose }}</button>
        <select @change="insertSavedReply" aria-label="Saved replies">
          <option value="">{{ t.savedReplies }}</option>
          <option v-for="r in savedReplies" :key="r.id" :value="r.id">{{ r.name }}</option>
        </select>
        <label style="margin:0">
          <input type="file" multiple style="display:none" @change="pickFiles" />
          <span class="pill" style="cursor:pointer">📎 {{ files.length || '' }}</span>
        </label>
      </template>
      <span class="spacer"></span>
      <span class="hint">{{ draftState }}</span>
    </div>
  </form>
</template>
