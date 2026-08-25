<script setup>
// Attachment cards + in-app preview overlay: images, PDF, audio, video,
// and text-ish files render in place; everything else downloads.
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { formatBytes } from '../format'

const props = defineProps({ attachments: { type: Array, required: true } })

const visible = computed(() => props.attachments.filter((a) => !a.content_id))
const preview = ref(null)
const textContent = ref(null)
const TEXT_LIMIT = 2 * 1048576

function kind(a) {
  const ct = a.content_type || ''
  if (/^image\/(png|jpeg|gif|webp)/.test(ct)) return 'image'
  if (ct === 'application/pdf') return 'pdf'
  if (/^audio\//.test(ct)) return 'audio'
  if (/^video\//.test(ct)) return 'video'
  if (/^text\//.test(ct) || /^application\/(json|xml|x-yaml)/.test(ct)) return 'text'
  return 'file'
}

function icon(a) {
  const k = kind(a)
  if (k === 'image') return '🖼'
  if (k === 'pdf') return '📕'
  if (k === 'audio') return '🎵'
  if (k === 'video') return '🎬'
  if (k === 'text') return '📄'
  const ext = extension(a)
  if (/^(xls|xlsx|csv|numbers)$/.test(ext)) return '📊'
  if (/^(doc|docx|odt|pages)$/.test(ext)) return '📝'
  if (/^(zip|gz|tar|rar|7z)$/.test(ext)) return '🗜'
  return '📎'
}

function extension(a) {
  const m = (a.filename || '').match(/\.(\w+)$/)
  return m ? m[1].toLowerCase() : (a.content_type || '').split('/')[1] || ''
}

async function open(a) {
  if (kind(a) === 'file') { window.open(a.url, '_blank'); return }
  preview.value = a
  textContent.value = null
  if (kind(a) === 'text') {
    if (a.byte_size > TEXT_LIMIT) { textContent.value = '(file too large to preview — download instead)'; return }
    textContent.value = await fetch(a.url, { credentials: 'same-origin' }).then((r) => r.text())
  }
}

function onKey(e) { if (e.key === 'Escape' && preview.value) preview.value = null }
onMounted(() => window.addEventListener('keydown', onKey))
onUnmounted(() => window.removeEventListener('keydown', onKey))
</script>

<template>
  <div v-if="visible.length" class="attachments">
    <button v-for="a in visible" :key="a.id" type="button" class="attachment-card"
            :title="`${a.filename} — ${formatBytes(a.byte_size)}`" @click="open(a)">
      <span v-if="kind(a) === 'image'" class="att-thumb">
        <img :src="a.url" :alt="a.filename" loading="lazy" />
      </span>
      <span v-else class="att-icon">{{ icon(a) }}</span>
      <span class="att-meta">
        <span class="att-name">{{ a.filename }}</span>
        <span class="att-info">{{ extension(a).toUpperCase() }} · {{ formatBytes(a.byte_size) }}</span>
      </span>
    </button>

    <Teleport to="body">
      <Transition name="fade">
        <div v-if="preview" class="preview-backdrop" @click.self="preview = null">
          <div class="preview-frame">
            <header class="preview-head">
              <strong class="att-name" style="min-width:0">{{ preview.filename }}</strong>
              <span class="att-info">{{ formatBytes(preview.byte_size) }}</span>
              <span style="flex:1"></span>
              <a :href="preview.url" :download="preview.filename" class="pill">Download</a>
              <button type="button" class="ghost" @click="preview = null" aria-label="Close">✕</button>
            </header>
            <div class="preview-body">
              <img v-if="kind(preview) === 'image'" :src="preview.url" :alt="preview.filename" />
              <iframe v-else-if="kind(preview) === 'pdf'" :src="preview.url" :title="preview.filename"></iframe>
              <audio v-else-if="kind(preview) === 'audio'" :src="preview.url" controls autoplay></audio>
              <video v-else-if="kind(preview) === 'video'" :src="preview.url" controls></video>
              <pre v-else-if="kind(preview) === 'text'">{{ textContent ?? 'Loading…' }}</pre>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>
