<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { api } from '../api'
import { t } from '../strings'

const props = defineProps({ conversation: { type: Object, required: true } })
const emit = defineEmits(['sent'])

const mode = ref('reply') // reply | note
const body = ref('')
const to = ref('')
const cc = ref('')
const files = ref([])
const savedReplies = ref([])
const busy = ref(false)
const draftState = ref('')
let draftTimer = null
let savedDraftBody = ''

const isNote = computed(() => mode.value === 'note')

onMounted(async () => {
  to.value = props.conversation.customer.email
  savedReplies.value = await api.get('/api/saved_replies')
  const drafts = await api.get('/api/drafts')
  const draft = drafts.find((d) => d.conversation_id === props.conversation.id)
  if (draft) { body.value = draft.body || ''; savedDraftBody = body.value }
})
onUnmounted(() => clearTimeout(draftTimer))

// Autosave draft, last-write-wins (B8).
watch(body, () => {
  if (isNote.value || body.value === savedDraftBody) return
  clearTimeout(draftTimer)
  draftTimer = setTimeout(async () => {
    await api.put('/api/drafts', {
      conversation_id: props.conversation.id,
      mailbox_id: props.conversation.mailbox_id,
      body: body.value,
      to: to.value.split(/[,;\s]+/).filter(Boolean),
      cc: cc.value.split(/[,;\s]+/).filter(Boolean),
    })
    savedDraftBody = body.value
    draftState.value = t.draftSaved
    setTimeout(() => (draftState.value = ''), 2000)
  }, 1500)
})

async function insertSavedReply(e) {
  const id = e.target.value
  e.target.value = ''
  if (!id) return
  const data = await api.get(`/api/saved_replies/${id}/render?conversation_id=${props.conversation.id}`)
  body.value = body.value ? `${body.value}\n${data.body}` : data.body
}

function pickFiles(e) { files.value = [...files.value, ...e.target.files] }

async function submit(close = false) {
  if (!body.value.trim()) return
  busy.value = true
  try {
    const form = new FormData()
    form.set('kind', isNote.value ? 'note' : 'outbound')
    form.set('body_text', body.value)
    if (!isNote.value) {
      to.value.split(/[,;\s]+/).filter(Boolean).forEach((x) => form.append('to[]', x))
      cc.value.split(/[,;\s]+/).filter(Boolean).forEach((x) => form.append('cc[]', x))
      if (close) form.set('close', 'true')
      files.value.forEach((f) => form.append('files[]', f))
    }
    await api.post(`/api/conversations/${props.conversation.id}/messages`, form)
    body.value = ''
    savedDraftBody = ''
    files.value = []
    emit('sent')
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <form class="composer" @submit.prevent="submit(false)">
    <div class="tabs" role="tablist">
      <button type="button" role="tab" :aria-selected="!isNote" :class="{ active: !isNote }" @click="mode = 'reply'">{{ t.reply }}</button>
      <button type="button" role="tab" :aria-selected="isNote" class="note-tab" :class="{ active: isNote }" @click="mode = 'note'">{{ t.note }}</button>
    </div>
    <div v-if="!isNote" class="fields">
      <div class="field-row">
        <label style="margin:0; width:24px">{{ t.to }}</label>
        <input v-model="to" aria-label="To" />
      </div>
      <div class="field-row">
        <label style="margin:0; width:24px">{{ t.cc }}</label>
        <input v-model="cc" aria-label="Cc" />
      </div>
    </div>
    <textarea v-model="body" :placeholder="isNote ? t.internalNote : `${t.reply}…`" rows="6"></textarea>
    <div class="actions">
      <template v-if="isNote">
        <button type="button" class="primary" :disabled="busy || !body.trim()" @click="submit(false)">{{ t.saveNote }}</button>
      </template>
      <template v-else>
        <button type="submit" class="primary" :disabled="busy || !body.trim()">{{ t.send }}</button>
        <button type="button" :disabled="busy || !body.trim()" @click="submit(true)">{{ t.sendAndClose }}</button>
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
