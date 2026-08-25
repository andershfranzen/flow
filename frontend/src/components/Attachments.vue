<script setup>
// Attachment cards + preview for stored message attachments.
import { ref, computed } from 'vue'
import { formatBytes } from '../format'
import PreviewOverlay from './PreviewOverlay.vue'
import { Image, FileText, Music, Film, FileSpreadsheet, Archive, Paperclip } from 'lucide-vue-next'

const props = defineProps({ attachments: { type: Array, required: true } })

const visible = computed(() => props.attachments.filter((a) => !a.content_id))
const preview = ref(null)
const broken = ref({})
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
  if (k === 'image') return Image
  if (k === 'pdf') return FileText
  if (k === 'audio') return Music
  if (k === 'video') return Film
  if (k === 'text') return FileText
  const ext = extension(a)
  if (/^(xls|xlsx|csv|numbers)$/.test(ext)) return FileSpreadsheet
  if (/^(doc|docx|odt|pages)$/.test(ext)) return FileText
  if (/^(zip|gz|tar|rar|7z)$/.test(ext)) return Archive
  return Paperclip
}

function extension(a) {
  const m = (a.filename || '').match(/\.(\w+)$/)
  return m ? m[1].toLowerCase() : (a.content_type || '').split('/')[1] || ''
}

async function open(a) {
  const k = kind(a)
  if (k === 'file') { window.open(a.url, '_blank'); return }
  const file = { name: a.filename, size: a.byte_size, url: a.url, kind: k, text: null }
  preview.value = file
  if (k === 'text') {
    file.text = a.byte_size > TEXT_LIMIT
      ? '(file too large to preview — download instead)'
      : await fetch(a.url, { credentials: 'same-origin' }).then((r) => r.text())
    preview.value = { ...file }
  }
}
</script>

<template>
  <div v-if="visible.length" class="attachments">
    <button v-for="a in visible" :key="a.id" type="button" class="attachment-card"
            :data-tip="`${a.filename} — ${formatBytes(a.byte_size)}`" @click="open(a)">
      <span v-if="kind(a) === 'image' && !broken[a.id]" class="att-thumb">
        <img :src="a.url" :alt="''" loading="lazy" @error="broken[a.id] = true" />
      </span>
      <span v-else class="att-icon"><component :is="icon(a)" :size="17" /></span>
      <span class="att-meta">
        <span class="att-name">{{ a.filename }}</span>
        <span class="att-info">{{ extension(a).toUpperCase() }} · {{ formatBytes(a.byte_size) }}</span>
      </span>
    </button>
    <PreviewOverlay v-if="preview" :file="preview" @close="preview = null" />
  </div>
</template>
