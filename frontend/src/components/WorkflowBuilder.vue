<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../api'

const workflows = ref([])
const meta = ref({ triggers: [], fields: [], operators: [], action_types: [], statuses: [] })
const mailboxes = ref([])
const agents = ref([])
const savedReplies = ref([])
const editing = ref(null) // deep copy of the workflow being built
const flash = ref('')
let dragIndex = null
let dragListIndex = null

const TRIGGER_LABELS = {
  'message.inbound': 'Customer mail arrives',
  'thread.created': 'New conversation starts',
  'message.outbound': 'Reply is sent',
  'thread.assigned': 'Conversation is assigned',
  'thread.status': 'Status changes',
}
const FIELD_LABELS = {
  subject: 'Subject', body: 'Body text', from_email: 'From address', from_domain: 'From domain',
  to_cc: 'To/Cc addresses', customer_email: 'Customer email', status: 'Status',
  assignee_email: 'Assignee email', has_attachment: 'Has attachment (yes/no)', tag: 'Tags',
}
const OPERATOR_LABELS = {
  contains: 'contains', not_contains: "doesn't contain", equals: 'is', not_equals: 'is not',
  starts_with: 'starts with', ends_with: 'ends with', matches_regex: 'matches regex',
}
const ACTION_LABELS = {
  assign: 'Assign to agent', unassign: 'Unassign', add_tag: 'Add tag', remove_tag: 'Remove tag',
  set_status: 'Set status', star: 'Star', move_mailbox: 'Move to mailbox',
  add_note: 'Add internal note', send_reply: 'Send reply to customer', forward_to: 'Forward to address',
}
const NO_VALUE_ACTIONS = ['unassign', 'star']

async function load() {
  const data = await api.get('/api/workflows')
  workflows.value = data.workflows
  meta.value = data.meta
}

onMounted(async () => {
  await load()
  mailboxes.value = await api.get('/api/mailboxes')
  agents.value = await api.get('/api/agents')
  savedReplies.value = await api.get('/api/saved_replies')
})

function ok(msg) { flash.value = msg; setTimeout(() => (flash.value = ''), 2500) }

function newWorkflow() {
  editing.value = {
    name: '', enabled: true, trigger: 'message.inbound', mailbox_id: null, match_type: 'all',
    conditions: [], actions: [{ type: 'add_tag', value: '' }],
  }
}

function edit(w) { editing.value = JSON.parse(JSON.stringify(w)) }

function addCondition() {
  editing.value.conditions.push({ field: 'subject', operator: 'contains', value: '' })
}

function addAction() { editing.value.actions.push({ type: 'set_status', value: 'closed' }) }

async function save() {
  const w = editing.value
  try {
    if (w.id) await api.patch(`/api/workflows/${w.id}`, w)
    else await api.post('/api/workflows', w)
    editing.value = null
    await load()
    ok('Workflow saved')
  } catch (e) {
    flash.value = e.details?.join(', ') || 'Could not save'
  }
}

async function toggle(w) {
  await api.patch(`/api/workflows/${w.id}`, { enabled: !w.enabled })
  await load()
}

async function remove(w) {
  if (!confirm(`Delete workflow "${w.name}"?`)) return
  await api.delete(`/api/workflows/${w.id}`)
  await load()
}

// Drag to reorder actions inside the builder (execution order)
function onDrop(index) {
  if (dragIndex === null || dragIndex === index) return
  const actions = editing.value.actions
  actions.splice(index, 0, actions.splice(dragIndex, 1)[0])
  dragIndex = null
}

// Drag to reorder workflow priority in the list
async function onListDrop(index) {
  if (dragListIndex === null || dragListIndex === index) return
  const list = [...workflows.value]
  list.splice(index, 0, list.splice(dragListIndex, 1)[0])
  workflows.value = list
  dragListIndex = null
  await api.patch('/api/workflows/reorder', { ids: list.map((w) => w.id) })
}

function valueControl(action) {
  if (action.type === 'assign') return 'agent'
  if (action.type === 'move_mailbox') return 'mailbox'
  if (action.type === 'set_status') return 'status'
  if (action.type === 'send_reply') return 'reply'
  if (action.type === 'add_note') return 'textarea'
  if (NO_VALUE_ACTIONS.includes(action.type)) return 'none'
  return 'text'
}
</script>

<template>
  <div>
    <p v-if="flash" class="ok-text">{{ flash }}</p>

    <!-- List -->
    <template v-if="!editing">
      <div class="form-actions" style="margin:0 0 12px">
        <button class="primary" @click="newWorkflow">New workflow</button>
        <span class="hint-text" style="margin:0">Rules run top to bottom on every matching event — drag to prioritise.</span>
      </div>
      <div v-for="(w, i) in workflows" :key="w.id" class="card wf-row" draggable="true"
           @dragstart="dragListIndex = i" @dragover.prevent @drop="onListDrop(i)">
        <span class="wf-grip" title="Drag to reorder">⠿</span>
        <div style="flex:1; min-width:0">
          <strong>{{ w.name }}</strong>
          <span class="pill" style="margin-left:8px">{{ TRIGGER_LABELS[w.trigger] }}</span>
          <span v-if="w.mailbox_id" class="pill">{{ mailboxes.find((m) => m.id === w.mailbox_id)?.name }}</span>
          <div class="hint-text" style="margin:2px 0 0">
            {{ w.conditions.length ? `${w.conditions.length} condition${w.conditions.length > 1 ? 's' : ''}` : 'always' }}
            → {{ w.actions.map((a) => ACTION_LABELS[a.type]).join(', ') }}
            · ran {{ w.runs_count }}×
          </div>
        </div>
        <button class="ghost" @click="edit(w)">Edit</button>
        <button class="ghost" @click="remove(w)">Delete</button>
        <label class="choice" style="margin:0">
          <input type="checkbox" :checked="w.enabled" @change="toggle(w)" /> On
        </label>
      </div>
      <p v-if="!workflows.length" class="empty">No workflows yet — automate your first triage rule.</p>
    </template>

    <!-- Builder canvas -->
    <form v-else class="wf-canvas" @submit.prevent="save">
      <div class="card" style="display:flex; gap:10px; align-items:end">
        <div style="flex:1">
          <label>Workflow name</label>
          <input v-model="editing.name" required placeholder="Billing triage" style="width:100%" />
        </div>
        <button type="submit" class="primary">Save</button>
        <button type="button" @click="editing = null">Cancel</button>
      </div>

      <div class="wf-node trigger">
        <div class="wf-node-head"><span class="wf-icon">⚡</span> When</div>
        <div class="wf-node-body">
          <select v-model="editing.trigger">
            <option v-for="tr in meta.triggers" :key="tr" :value="tr">{{ TRIGGER_LABELS[tr] }}</option>
          </select>
          <select v-model="editing.mailbox_id">
            <option :value="null">in any mailbox</option>
            <option v-for="m in mailboxes" :key="m.id" :value="m.id">in {{ m.name }}</option>
          </select>
        </div>
      </div>

      <div class="wf-connector"></div>

      <div class="wf-node condition">
        <div class="wf-node-head">
          <span class="wf-icon">❓</span> If
          <select v-model="editing.match_type" style="margin-left:6px">
            <option value="all">all conditions match</option>
            <option value="any">any condition matches</option>
          </select>
          <span v-if="!editing.conditions.length" class="hint-text" style="margin:0 0 0 6px">(always runs)</span>
        </div>
        <div class="wf-node-body" style="flex-direction:column; align-items:stretch">
          <div v-for="(c, i) in editing.conditions" :key="i" class="wf-step">
            <select v-model="c.field">
              <option v-for="f in meta.fields" :key="f" :value="f">{{ FIELD_LABELS[f] }}</option>
            </select>
            <select v-model="c.operator">
              <option v-for="op in meta.operators" :key="op" :value="op">{{ OPERATOR_LABELS[op] }}</option>
            </select>
            <input v-model="c.value" placeholder="value" style="flex:1; min-width:80px" />
            <button type="button" class="ghost" @click="editing.conditions.splice(i, 1)">✕</button>
          </div>
          <button type="button" class="ghost" style="align-self:flex-start" @click="addCondition">＋ Add condition</button>
        </div>
      </div>

      <div class="wf-connector"></div>

      <div v-for="(a, i) in editing.actions" :key="i" style="display:contents">
        <div class="wf-node action" draggable="true"
             @dragstart="dragIndex = i" @dragover.prevent @drop="onDrop(i)">
          <div class="wf-node-head">
            <span class="wf-grip" title="Drag to reorder">⠿</span>
            <span class="wf-icon">⚙</span> Then
            <select v-model="a.type" style="margin-left:6px">
              <option v-for="tp in meta.action_types" :key="tp" :value="tp">{{ ACTION_LABELS[tp] }}</option>
            </select>
            <span class="spacer" style="flex:1"></span>
            <button v-if="editing.actions.length > 1" type="button" class="ghost" @click="editing.actions.splice(i, 1)">✕</button>
          </div>
          <div class="wf-node-body" v-if="valueControl(a) !== 'none'">
            <select v-if="valueControl(a) === 'agent'" v-model="a.value" style="flex:1">
              <option v-for="ag in agents" :key="ag.id" :value="String(ag.id)">{{ ag.name }}</option>
            </select>
            <select v-else-if="valueControl(a) === 'mailbox'" v-model="a.value" style="flex:1">
              <option v-for="m in mailboxes" :key="m.id" :value="String(m.id)">{{ m.name }}</option>
            </select>
            <select v-else-if="valueControl(a) === 'status'" v-model="a.value" style="flex:1">
              <option v-for="st in meta.statuses" :key="st" :value="st">{{ st }}</option>
            </select>
            <template v-else-if="valueControl(a) === 'reply'">
              <select v-model="a.value" style="flex:1">
                <option value="">Custom text…</option>
                <option v-for="r in savedReplies" :key="r.id" :value="String(r.id)">Saved reply: {{ r.name }}</option>
              </select>
              <textarea v-if="!savedReplies.some((r) => String(r.id) === a.value)" v-model="a.value"
                        rows="2" placeholder="Reply text — {{customer.name}} works" style="flex:2"></textarea>
            </template>
            <textarea v-else-if="valueControl(a) === 'textarea'" v-model="a.value" rows="2"
                      placeholder="Note text" style="flex:1"></textarea>
            <input v-else v-model="a.value" :placeholder="a.type === 'forward_to' ? 'someone@example.com' : 'value'" style="flex:1" />
          </div>
        </div>
        <div class="wf-connector"></div>
      </div>

      <button type="button" class="ghost" style="align-self:center" @click="addAction">＋ Add action</button>
    </form>
  </div>
</template>
