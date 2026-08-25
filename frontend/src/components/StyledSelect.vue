<script setup>
// App-styled replacement for native <select>: pill button + popover listbox.
// options: array of { value, label } (or plain strings). `searchable` adds a
// filter input for long lists (e.g. timezones).
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue'
import { ChevronDown, Check } from 'lucide-vue-next'

const props = defineProps({
  modelValue: { default: null },
  options: { type: Array, required: true },
  placeholder: { type: String, default: 'Select…' },
  searchable: { type: Boolean, default: false },
  ariaLabel: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue', 'change'])

const open = ref(false)
const active = ref(-1)
const filter = ref('')
const rootEl = ref(null)
const listEl = ref(null)
const searchEl = ref(null)

const normalized = computed(() =>
  props.options.map((o) => (typeof o === 'object' && o !== null ? o : { value: o, label: String(o) })))
const visible = computed(() => {
  if (!filter.value) return normalized.value
  const q = filter.value.toLowerCase()
  return normalized.value.filter((o) => o.label.toLowerCase().includes(q))
})
const selected = computed(() => normalized.value.find((o) => o.value === props.modelValue))

function toggle() { open.value ? close() : openList() }
function openList() {
  open.value = true
  filter.value = ''
  active.value = visible.value.findIndex((o) => o.value === props.modelValue)
  nextTick(() => {
    searchEl.value?.focus()
    listEl.value?.querySelector('.sel-option.selected')?.scrollIntoView({ block: 'nearest' })
  })
}
function close() { open.value = false; active.value = -1 }
function choose(option) {
  emit('update:modelValue', option.value)
  emit('change', option.value)
  close()
  rootEl.value?.querySelector('.sel-button')?.focus()
}

function onKeydown(e) {
  if (!open.value && ['Enter', ' ', 'ArrowDown', 'ArrowUp'].includes(e.key)) {
    e.preventDefault()
    return openList()
  }
  if (!open.value) return
  if (e.key === 'Escape') { e.preventDefault(); close() }
  else if (e.key === 'ArrowDown') { e.preventDefault(); move(1) }
  else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1) }
  else if (e.key === 'Enter') { e.preventDefault(); if (visible.value[active.value]) choose(visible.value[active.value]) }
}
function move(delta) {
  const count = visible.value.length
  if (!count) return
  active.value = (active.value + delta + count) % count
  nextTick(() => listEl.value?.querySelectorAll('.sel-option')[active.value]?.scrollIntoView({ block: 'nearest' }))
}
watch(filter, () => (active.value = visible.value.length ? 0 : -1))

function onDocDown(e) { if (!rootEl.value?.contains(e.target)) close() }
watch(open, (isOpen) => {
  if (isOpen) document.addEventListener('pointerdown', onDocDown)
  else document.removeEventListener('pointerdown', onDocDown)
})
onBeforeUnmount(() => document.removeEventListener('pointerdown', onDocDown))
</script>

<template>
  <div ref="rootEl" class="sel" @keydown="onKeydown">
    <button type="button" class="sel-button" :aria-expanded="open" :aria-label="ariaLabel || placeholder"
            aria-haspopup="listbox" @click="toggle">
      <span class="sel-value" :class="{ placeholder: !selected }">{{ selected?.label ?? placeholder }}</span>
      <ChevronDown :size="15" class="sel-chevron" :class="{ open }" />
    </button>
    <div v-if="open" class="sel-pop">
      <input v-if="searchable" ref="searchEl" v-model="filter" class="sel-search"
             placeholder="Filter…" aria-label="Filter options" />
      <div ref="listEl" class="sel-list" role="listbox">
        <button v-for="(o, i) in visible" :key="String(o.value)" type="button" class="sel-option"
                role="option" :aria-selected="o.value === modelValue"
                :class="{ selected: o.value === modelValue, active: i === active }"
                @pointerenter="active = i" @click="choose(o)">
          <span class="sel-option-label">{{ o.label }}</span>
          <Check v-if="o.value === modelValue" :size="14" />
        </button>
        <div v-if="!visible.length" class="sel-empty">No matches</div>
      </div>
    </div>
  </div>
</template>
