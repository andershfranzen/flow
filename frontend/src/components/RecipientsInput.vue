<script>
// Shared across every RecipientsInput instance (script setup vars are
// per-instance): the in-flight chip drag, so To ↔ Cc hand-offs work.
let dragPayload = null
</script>

<script setup>
// Email chips like a real mail client: a finished address becomes a badge;
// Backspace on an empty input turns the last badge back into editable text,
// and clicking a chip does the same. Shift+click marks chips; dragging moves
// a chip (or every marked chip) between fields (e.g. To ↔ Cc) via a
// module-level payload — same-window only, which is all HTML5 DnD gives us.
import { ref, nextTick } from 'vue'
import { X } from 'lucide-vue-next'

const props = defineProps({
  modelValue: { type: Array, required: true },
  placeholder: { type: String, default: '' },
  ariaLabel: { type: String, default: 'Recipients' },
})
const emit = defineEmits(['update:modelValue', 'changed'])

const text = ref('')
const inputEl = ref(null)
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

function pendingParts() {
  return text.value.split(/[,;\s]+/).map((p) => p.trim()).filter(Boolean)
}

function commit() {
  const parts = pendingParts()
  if (!parts.length) return
  emit('update:modelValue', [...props.modelValue, ...parts])
  emit('changed')
  text.value = ''
}

function onKeydown(e) {
  if (e.key === 'Enter' || e.key === ',' || e.key === ';' || (e.key === ' ' && text.value.trim())) {
    e.preventDefault()
    commit()
  } else if (e.key === 'Tab' && text.value.trim()) {
    commit() // let Tab still move focus afterwards
  } else if (e.key === 'Backspace' && text.value === '' && props.modelValue.length) {
    e.preventDefault()
    marked.value = new Set()
    const chips = [...props.modelValue]
    text.value = chips.pop() // back to editable text, not just deleted
    emit('update:modelValue', chips)
    emit('changed')
    nextTick(() => inputEl.value?.setSelectionRange(text.value.length, text.value.length))
  }
}

function onPaste(e) {
  const pasted = e.clipboardData?.getData('text') || ''
  if (!/[,;\s]/.test(pasted)) return // single token: let it type normally
  e.preventDefault()
  text.value += pasted
  commit()
}

function remove(index) {
  marked.value = new Set() // indices shift; stale marks would drag the wrong chip
  emit('update:modelValue', props.modelValue.filter((_, i) => i !== index))
  emit('changed')
}

const dragOver = ref(false)
const marked = ref(new Set())

function onChipClick(index, e) {
  if (e.shiftKey) {
    const next = new Set(marked.value)
    next.has(index) ? next.delete(index) : next.add(index)
    marked.value = next
    return
  }
  // Plain click: pull the chip back into the input for editing.
  // Half-typed text becomes chips in the same emit — props lag emits.
  const chips = [...props.modelValue, ...pendingParts()]
  text.value = chips.splice(index, 1)[0]
  marked.value = new Set()
  emit('update:modelValue', chips)
  emit('changed')
  nextTick(() => {
    inputEl.value?.focus()
    inputEl.value?.setSelectionRange(text.value.length, text.value.length)
  })
}

function onChipDragStart(index, e) {
  e.dataTransfer.effectAllowed = 'move'
  const indexes = marked.value.has(index) ? [...marked.value].sort((a, b) => a - b) : [index]
  const emails = indexes.map((i) => props.modelValue[i])
  e.dataTransfer.setData('text/plain', emails.join(', '))
  dragPayload = {
    emails,
    removeFromSource: () => {
      const gone = new Set(indexes)
      marked.value = new Set()
      emit('update:modelValue', props.modelValue.filter((_, i) => !gone.has(i)))
      emit('changed')
    },
  }
}

function onChipDragEnd() { dragPayload = null }

function onDrop(e) {
  dragOver.value = false
  if (!dragPayload) return
  e.preventDefault()
  const { emails, removeFromSource } = dragPayload
  dragPayload = null
  const fresh = emails.filter((x) => !props.modelValue.includes(x))
  if (!fresh.length) return // dropped back where it came from
  removeFromSource()
  emit('update:modelValue', [...props.modelValue, ...fresh])
  emit('changed')
}

defineExpose({ commit })
</script>

<template>
  <div class="recipients" :class="{ 'drag-over': dragOver }" @click="inputEl?.focus()"
       @dragover.prevent="dragOver = !!dragPayload" @dragleave="dragOver = false" @drop="onDrop">
    <span v-for="(email, i) in modelValue" :key="`${email}-${i}`"
          class="recipient-chip" :class="{ invalid: !EMAIL_RE.test(email), marked: marked.has(i) }"
          draggable="true" @dragstart="onChipDragStart(i, $event)" @dragend="onChipDragEnd"
          @click.stop="onChipClick(i, $event)">
      {{ email }}
      <button type="button" class="chip-x" :aria-label="`Remove ${email}`" tabindex="-1"
              @click.stop="remove(i)"><X :size="11" /></button>
    </span>
    <input ref="inputEl" v-model="text" :placeholder="modelValue.length ? '' : placeholder"
           :aria-label="ariaLabel" autocomplete="off" spellcheck="false"
           @keydown="onKeydown" @paste="onPaste" @blur="commit" />
  </div>
</template>
