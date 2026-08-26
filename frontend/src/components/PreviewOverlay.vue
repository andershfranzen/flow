<script setup>
// Shared preview overlay: server attachments and local pending files alike.
// file: { name, size, url, kind: image|pdf|audio|video|text, text }
import { onMounted, onUnmounted } from 'vue'
import { formatBytes } from '../format'
import { X, Download } from 'lucide-vue-next'

defineProps({ file: { type: Object, required: true } })
const emit = defineEmits(['close'])

function onKey(e) { if (e.key === 'Escape') emit('close') }
onMounted(() => window.addEventListener('keydown', onKey))
onUnmounted(() => window.removeEventListener('keydown', onKey))
</script>

<template>
  <Teleport to="body">
    <div class="preview-backdrop" @click.self="emit('close')">
      <div class="preview-frame">
        <header class="preview-head">
          <strong class="att-name" style="min-width:0">{{ file.name }}</strong>
          <span class="att-info">{{ formatBytes(file.size) }}</span>
          <span style="flex:1"></span>
          <a v-if="file.url" :href="file.url" :download="file.name" class="pill" style="display:inline-flex; align-items:center; gap:4px"><Download :size="12" /> Download</a>
          <button type="button" class="ghost" @click="emit('close')" aria-label="Close"><X :size="15" /></button>
        </header>
        <div class="preview-body">
          <img v-if="file.kind === 'image'" :src="file.url" :alt="file.name" />
          <iframe v-else-if="file.kind === 'pdf'" :src="file.url" :title="file.name" sandbox></iframe>
          <audio v-else-if="file.kind === 'audio'" :src="file.url" controls autoplay></audio>
          <video v-else-if="file.kind === 'video'" :src="file.url" controls></video>
          <pre v-else-if="file.kind === 'text'">{{ file.text ?? 'Loading…' }}</pre>
          <p v-else style="padding:40px; color:var(--muted)">No preview for this type.</p>
        </div>
      </div>
    </div>
  </Teleport>
</template>
