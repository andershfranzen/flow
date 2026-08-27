<script setup>
import { nextTick, onUnmounted, ref, watch } from 'vue'
import { t } from '../strings'
import { dialogState as d } from '../dialog'

const inputEl = ref(null)
const okEl = ref(null)

// Esc cancels no matter where focus sits, like the native dialogs did.
const onKey = (e) => { if (e.key === 'Escape') { e.stopPropagation(); cancel() } }

watch(() => d.open, async (open) => {
  if (!open) { window.removeEventListener('keydown', onKey, true); return }
  window.addEventListener('keydown', onKey, true)
  await nextTick()
  ;(d.kind === 'prompt' ? inputEl.value : okEl.value)?.focus()
})
onUnmounted(() => window.removeEventListener('keydown', onKey, true))

function finish(result) {
  d.open = false
  d.resolve?.(result)
  d.resolve = null
}

function cancel() {
  finish(d.kind === 'confirm' ? false : d.kind === 'prompt' ? null : undefined)
}

function submit() {
  finish(d.kind === 'confirm' ? true : d.kind === 'prompt' ? d.input : undefined)
}
</script>

<template>
  <div v-if="d.open" class="modal-backdrop" @click.self="cancel">
    <form class="modal modal-dialog" @submit.prevent="submit">
      <p class="dialog-message">{{ d.message }}</p>
      <input v-if="d.kind === 'prompt'" ref="inputEl" v-model="d.input"
             :placeholder="d.placeholder" style="width:100%" />
      <div style="display:flex; gap:8px; justify-content:flex-end; margin-top:16px">
        <button v-if="d.kind !== 'alert'" type="button" @click="cancel">{{ t.cancel }}</button>
        <button ref="okEl" type="submit" class="primary" :class="{ danger: d.danger }">OK</button>
      </div>
    </form>
  </div>
</template>
