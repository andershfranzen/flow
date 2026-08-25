<script setup>
// Files staged in a composer before sending: name, size, type, removable.
import { formatBytes } from '../format'

defineProps({ files: { type: Array, required: true } })
const emit = defineEmits(['remove'])

function icon(f) {
  const t = f.type || ''
  if (t.startsWith('image/')) return '🖼'
  if (t === 'application/pdf') return '📕'
  if (t.startsWith('audio/')) return '🎵'
  if (t.startsWith('video/')) return '🎬'
  if (t.startsWith('text/')) return '📄'
  return '📎'
}
</script>

<template>
  <div v-if="files.length" class="pending-files">
    <span v-for="(f, i) in files" :key="`${f.name}-${i}`" class="pending-file" :title="f.name">
      <span>{{ icon(f) }}</span>
      <span class="att-name">{{ f.name }}</span>
      <span class="att-info">{{ formatBytes(f.size) }}</span>
      <button type="button" class="chip-x" :aria-label="`Remove ${f.name}`" @click="emit('remove', i)">✕</button>
    </span>
  </div>
</template>
