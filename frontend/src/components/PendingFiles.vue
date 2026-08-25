<script setup>
// Files staged before sending: icon, name, size — clickable for a local
// preview (object URL), removable.
import { ref } from 'vue'
import { formatBytes } from '../format'
import PreviewOverlay from './PreviewOverlay.vue'

defineProps({ files: { type: Array, required: true } })
const emit = defineEmits(['remove'])
const preview = ref(null)

function kind(f) {
  const t = f.type || ''
  if (t.startsWith('image/')) return 'image'
  if (t === 'application/pdf') return 'pdf'
  if (t.startsWith('audio/')) return 'audio'
  if (t.startsWith('video/')) return 'video'
  if (t.startsWith('text/') || /^application\/(json|xml)/.test(t)) return 'text'
  return 'file'
}

function icon(f) {
  const k = kind(f)
  return { image: '🖼', pdf: '📕', audio: '🎵', video: '🎬', text: '📄' }[k] || '📎'
}

async function open(f) {
  const k = kind(f)
  const file = { name: f.name, size: f.size, kind: k, url: null, text: null }
  if (k === 'text') file.text = await f.text()
  else if (k !== 'file') file.url = URL.createObjectURL(f)
  preview.value = file
}

function close() {
  if (preview.value?.url) URL.revokeObjectURL(preview.value.url)
  preview.value = null
}
</script>

<template>
  <div v-if="files.length" class="pending-files">
    <span v-for="(f, i) in files" :key="`${f.name}-${i}`" class="pending-file"
          :data-tip="`${f.name} — ${formatBytes(f.size)}`" role="button" tabindex="0"
          @click="open(f)" @keydown.enter="open(f)">
      <span>{{ icon(f) }}</span>
      <span class="att-name">{{ f.name }}</span>
      <span class="att-info">{{ formatBytes(f.size) }}</span>
      <button type="button" class="chip-x" :aria-label="`Remove ${f.name}`" @click.stop="emit('remove', i)">✕</button>
    </span>
    <PreviewOverlay v-if="preview" :file="preview" @close="close" />
  </div>
</template>
