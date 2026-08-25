<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../api'
import { t } from '../strings'
import { useSession } from '../stores/session'
import RichEditor from './RichEditor.vue'
import RecipientsInput from './RecipientsInput.vue'
import PendingFiles from './PendingFiles.vue'

const props = defineProps({
  mailboxes: { type: Array, required: true },
  defaultMailboxId: { type: Number, default: null },
})
const emit = defineEmits(['close', 'created'])

const session = useSession()
const editor = ref(null)
const agents = ref([])
const files = ref([])
const busy = ref(false)
const error = ref('')
const form = ref({
  mailbox_id: props.defaultMailboxId || props.mailboxes[0]?.id,
  assignee_id: session.agent?.id,
  status: 'active',
  to: [], cc: [], subject: '',
})

onMounted(async () => {
  agents.value = await api.get('/api/agents')
})

function pickFiles(e) { files.value = [...files.value, ...e.target.files] }

async function submit() {
  if (!form.value.to.length) { error.value = 'Add at least one recipient'; return }
  if (!editor.value?.hasContent()) { error.value = 'Write a message first'; return }
  busy.value = true
  error.value = ''
  try {
    const fd = new FormData()
    fd.set('mailbox_id', form.value.mailbox_id)
    fd.set('assignee_id', form.value.assignee_id || '')
    fd.set('status', form.value.status)
    fd.set('subject', form.value.subject)
    form.value.to.forEach((x) => fd.append('to[]', x))
    form.value.cc.forEach((x) => fd.append('cc[]', x))
    fd.set('body_text', editor.value.getText())
    fd.set('body_html', editor.value.getOutgoingHtml())
    files.value.forEach((f) => fd.append('files[]', f))
    editor.value.getInlineImages().forEach((f) => fd.append('inline_images[]', f))
    const conv = await api.post('/api/conversations', fd)
    emit('created', conv)
  } catch (e) {
    error.value = e.details?.join(', ') || 'Could not send'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="modal-backdrop" @click.self="emit('close')">
    <form class="modal modal-wide" @submit.prevent="submit">
      <h2>{{ t.newConversation }}</h2>
      <div class="modal-grid">
        <div>
          <label>Mailbox</label>
          <select v-model="form.mailbox_id" style="width:100%">
            <option v-for="m in mailboxes" :key="m.id" :value="m.id">{{ m.name }} ({{ m.address }})</option>
          </select>
        </div>
        <div>
          <label>{{ t.assignTo }}</label>
          <select v-model="form.assignee_id" style="width:100%">
            <option :value="null">{{ t.unassigned }}</option>
            <option v-for="a in agents" :key="a.id" :value="a.id">
              {{ a.name }}{{ a.id === session.agent?.id ? ' (me)' : '' }}
            </option>
          </select>
        </div>
        <div>
          <label>Status after send</label>
          <select v-model="form.status" style="width:100%">
            <option value="active">{{ t.statuses.active }}</option>
            <option value="pending">{{ t.statuses.pending }}</option>
            <option value="closed">{{ t.statuses.closed }} (log &amp; archive)</option>
          </select>
        </div>
      </div>
      <div style="display:flex; flex-direction:column; gap:10px; margin-top:10px">
        <div>
          <label>{{ t.to }}</label>
          <RecipientsInput v-model="form.to" placeholder="customer@example.com" aria-label="To" />
        </div>
        <div>
          <label>{{ t.cc }}</label>
          <RecipientsInput v-model="form.cc" aria-label="Cc" />
        </div>
        <div>
          <label>{{ t.subject }}</label>
          <input v-model="form.subject" required style="width:100%" />
        </div>
        <div class="modal-editor">
          <RichEditor ref="editor" placeholder="Write your message — paste screenshots directly…" />
        </div>
        <PendingFiles :files="files" @remove="(i) => files.splice(i, 1)" />
      </div>
      <p v-if="error" class="error-text" style="margin:8px 0 0">{{ error }}</p>
      <div style="display:flex; gap:8px; align-items:center; margin-top:14px">
        <button type="submit" class="primary" :disabled="busy">{{ t.send }}</button>
        <label style="margin:0">
          <input type="file" multiple style="display:none" @change="pickFiles" />
          <span class="pill" style="cursor:pointer">📎 {{ files.length || 'Attach' }}</span>
        </label>
        <span class="spacer" style="flex:1"></span>
        <button type="button" @click="emit('close')">{{ t.cancel }}</button>
      </div>
    </form>
  </div>
</template>
