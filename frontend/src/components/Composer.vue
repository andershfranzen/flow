<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { api } from '../api'
import { t } from '../strings'
import { useSession } from '../stores/session'
import { useInbox } from '../stores/inbox'
import RichEditor from './RichEditor.vue'
import RecipientsInput from './RecipientsInput.vue'
import PendingFiles from './PendingFiles.vue'
import { Paperclip, X } from 'lucide-vue-next'
import StyledSelect from './StyledSelect.vue'

const props = defineProps({
  conversation: { type: Object, required: true },
  forwardSeed: { type: Object, default: null },
})
const emit = defineEmits(['sent'])
const session = useSession()
const inbox = useInbox()

const mode = ref('reply') // reply | note
const editor = ref(null)
const to = ref([])
const cc = ref([])
const subject = ref(null) // non-null = forward mode (B16)
const files = ref([])
const savedReplies = ref([])
const busy = ref(false)
const draftState = ref('')
let draftTimer = null
let savedDraftBody = ''

const isNote = computed(() => mode.value === 'note')

// What will actually be appended on send (A19): agent > mailbox > org default.
const effectiveSignature = computed(() =>
  session.agent?.signature?.trim() ||
  inbox.mailboxes.find((m) => m.id === props.conversation.mailbox_id)?.signature ||
  session.org?.default_signature || ''
)
const includeSignature = ref(true)

// Reply-all prefill (B7): everyone from the last inbound, never our mailbox.
watch(() => props.conversation.reply_all, (ra) => {
  if (!ra) return
  to.value = [...ra.to]
  cc.value = [...ra.cc]
}, { immediate: true })

watch(() => props.forwardSeed, (seed) => {
  if (!seed || !editor.value) return
  mode.value = 'reply'
  subject.value = seed.subject
  if (!seed.keepTo) to.value = []
  if (seed.html != null) editor.value.setHtml(seed.html)
  else editor.value.setText(seed.body || '')
  editor.value.focus()
})

function cancelForward() {
  subject.value = null
  const ra = props.conversation.reply_all
  to.value = ra ? [...ra.to] : [props.conversation.customer.email]
  editor.value.clear()
}

onMounted(async () => {
  savedReplies.value = await api.get('/api/saved_replies')
  const drafts = await api.get('/api/drafts')
  const draft = drafts.find((d) => d.conversation_id === props.conversation.id)
  if (draft?.body && editor.value) {
    editor.value.setHtml(draft.body) // agent's own draft html
    savedDraftBody = draft.body
    if (draft.to?.length) to.value = [...draft.to]
    if (draft.cc?.length) cc.value = [...draft.cc]
  }
})
onUnmounted(() => clearTimeout(draftTimer))

// Autosave draft, last-write-wins (B8).
function onInput() {
  if (isNote.value) return
  clearTimeout(draftTimer)
  draftTimer = setTimeout(async () => {
    const html = editor.value?.getRawHtml() || ''
    if (html === savedDraftBody) return
    await api.put('/api/drafts', {
      conversation_id: props.conversation.id,
      mailbox_id: props.conversation.mailbox_id,
      body: html,
      to: to.value,
      cc: cc.value,
    })
    savedDraftBody = html
    draftState.value = t.draftSaved
    setTimeout(() => (draftState.value = ''), 2000)
  }, 1500)
}

function pickFiles(e) { files.value = [...files.value, ...e.target.files] }

async function submit(close = false) {
  if (!editor.value?.hasContent()) return
  busy.value = true
  try {
    const form = new FormData()
    form.set('kind', isNote.value ? 'note' : 'outbound')
    form.set('body_text', editor.value.getText())
    form.set('body_html', editor.value.getOutgoingHtml())
    if (!isNote.value) {
      to.value.forEach((x) => form.append('to[]', x))
      cc.value.forEach((x) => form.append('cc[]', x))
      if (subject.value) form.set('subject', subject.value)
      if (!includeSignature.value) form.set('skip_signature', '1')
      if (close) form.set('close', 'true')
      files.value.forEach((f) => form.append('files[]', f))
      editor.value.getInlineImages().forEach((f) => form.append('inline_images[]', f))
    }
    await api.post(`/api/conversations/${props.conversation.id}/messages`, form)
    editor.value.clear()
    savedDraftBody = ''
    files.value = []
    subject.value = null
    const ra = props.conversation.reply_all
    to.value = ra ? [...ra.to] : [props.conversation.customer.email]
    cc.value = ra ? [...ra.cc] : []
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
  const escaped = data.body.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>')
  editor.value.setHtml(editor.value.getRawHtml() + (editor.value.getText() ? '<br>' : '') + escaped)
  onInput()
}
</script>

<template>
  <form class="composer" @submit.prevent="submit(false)">
    <div class="tabs" role="tablist">
      <button type="button" role="tab" :aria-selected="!isNote" :class="{ active: !isNote }" @click="mode = 'reply'">{{ t.reply }}</button>
      <button type="button" role="tab" :aria-selected="isNote" class="note-tab" :class="{ active: isNote }" @click="mode = 'note'">{{ t.note }}</button>
    </div>
    <div v-if="!isNote" class="fields">
      <div v-if="subject !== null" class="field-row">
        <label style="margin:0; width:28px">Fwd</label>
        <input v-model="subject" aria-label="Subject" />
        <button type="button" class="ghost" @click="cancelForward" data-tip="Cancel forward"><X :size="14" /></button>
      </div>
      <div class="field-row">
        <label style="margin:0; width:28px">{{ t.to }}</label>
        <RecipientsInput v-model="to" aria-label="To" :placeholder="subject !== null ? 'forward to…' : ''"
                         @changed="onInput" />
      </div>
      <div class="field-row">
        <label style="margin:0; width:28px">{{ t.cc }}</label>
        <RecipientsInput v-model="cc" aria-label="Cc" @changed="onInput" />
      </div>
    </div>
    <RichEditor ref="editor" :placeholder="isNote ? `${t.internalNote} — @name notifies` : `${t.reply}…`"
                @input="onInput" />
    <PendingFiles :files="files" @remove="(i) => files.splice(i, 1)" />
    <div v-if="!isNote && effectiveSignature && includeSignature" class="sig-preview">
      <span class="sig-label">signature</span>
      <div v-html="effectiveSignature"></div>
    </div>
    <div class="actions">
      <template v-if="isNote">
        <button type="button" class="primary" :disabled="busy" @click="submit(false)">{{ t.saveNote }}</button>
      </template>
      <template v-else>
        <button type="submit" class="primary" :disabled="busy">{{ t.send }}</button>
        <button type="button" :disabled="busy" @click="submit(true)">{{ t.sendAndClose }}</button>
        <StyledSelect :model-value="''" :placeholder="t.savedReplies" aria-label="Saved replies"
                      @change="(v) => insertSavedReply({ target: { value: v } })"
                      :options="savedReplies.map((r) => ({ value: r.id, label: r.name }))" />
        <label style="margin:0">
          <input type="file" multiple style="display:none" @change="pickFiles" />
          <span class="pill" style="cursor:pointer; display:inline-flex; align-items:center; gap:4px" data-tip="Attach files"><Paperclip :size="13" /> {{ files.length || '' }}</span>
        </label>
      </template>
      <span class="spacer"></span>
      <span class="hint">{{ draftState }}</span>
      <button v-if="!isNote && effectiveSignature" type="button" class="ghost sig-toggle"
              :data-tip="includeSignature ? 'Send this mail without the signature' : 'Append the signature again'"
              @click="includeSignature = !includeSignature">
        {{ includeSignature ? 'Skip signature' : 'Add signature' }}
      </button>
    </div>
  </form>
</template>
