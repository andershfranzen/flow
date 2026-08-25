<script setup>
// Email chips like a real mail client: a finished address becomes a badge;
// Backspace on an empty input turns the last badge back into editable text.
import { ref, nextTick } from 'vue'

const props = defineProps({
  modelValue: { type: Array, required: true },
  placeholder: { type: String, default: '' },
  ariaLabel: { type: String, default: 'Recipients' },
})
const emit = defineEmits(['update:modelValue', 'changed'])

const text = ref('')
const inputEl = ref(null)
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

function commit() {
  const parts = text.value.split(/[,;\s]+/).map((p) => p.trim()).filter(Boolean)
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
  emit('update:modelValue', props.modelValue.filter((_, i) => i !== index))
  emit('changed')
}

defineExpose({ commit })
</script>

<template>
  <div class="recipients" @click="inputEl?.focus()">
    <span v-for="(email, i) in modelValue" :key="`${email}-${i}`"
          class="recipient-chip" :class="{ invalid: !EMAIL_RE.test(email) }">
      {{ email }}
      <button type="button" class="chip-x" :aria-label="`Remove ${email}`" tabindex="-1"
              @click.stop="remove(i)">✕</button>
    </span>
    <input ref="inputEl" v-model="text" :placeholder="modelValue.length ? '' : placeholder"
           :aria-label="ariaLabel" autocomplete="off" spellcheck="false"
           @keydown="onKeydown" @paste="onPaste" @blur="commit" />
  </div>
</template>
