<script setup>
// Shared rich-text editor: toolbar, contenteditable, inline image paste (A20).
// Parents read content via the exposed methods; pasted images upload as CID
// inline attachments named by their local placeholder.
import { ref, watch, onMounted } from 'vue'
import { dialog } from '../dialog'
import { Link2, List, ListOrdered, Quote, RemoveFormatting } from 'lucide-vue-next'

const props = defineProps({
  placeholder: { type: String, default: '' },
  modelValue: { type: String, default: null }, // optional two-way html binding
})
const emit = defineEmits(['input', 'update:modelValue'])

const editorEl = ref(null)
const inlineImages = ref([]) // { cid, file }

onMounted(() => {
  if (props.modelValue != null && editorEl.value) editorEl.value.innerHTML = props.modelValue
})
watch(() => props.modelValue, (v) => {
  if (v == null || !editorEl.value) return
  if (document.activeElement !== editorEl.value && editorEl.value.innerHTML !== v) {
    editorEl.value.innerHTML = v
  }
})

function onNativeInput() {
  emit('input')
  if (props.modelValue != null) emit('update:modelValue', editorEl.value.innerHTML)
}

function exec(command, arg = null) {
  editorEl.value?.focus()
  document.execCommand(command, false, arg)
  onNativeInput()
}

async function addLink() {
  // The modal steals focus, so preserve the text selection across the dialog.
  const range = window.getSelection()?.rangeCount ? window.getSelection().getRangeAt(0).cloneRange() : null
  const url = await dialog.prompt('Link URL:', { initial: 'https://' })
  if (!url) return
  if (range) {
    const sel = window.getSelection()
    sel.removeAllRanges()
    sel.addRange(range)
  }
  exec('createLink', url)
}

function startResize(e) {
  const startY = e.clientY
  const startH = editorEl.value.offsetHeight
  // Grip sits below the editor: dragging down grows it.
  const move = (ev) => { editorEl.value.style.height = `${Math.max(120, startH + (ev.clientY - startY))}px` }
  const up = () => {
    window.removeEventListener('pointermove', move)
    window.removeEventListener('pointerup', up)
  }
  window.addEventListener('pointermove', move)
  window.addEventListener('pointerup', up)
}

function clearFormatting() {
  exec('removeFormat')
  exec('unlink')
  exec('formatBlock', 'div') // lift blockquotes/lists back to plain lines
}

function onPaste(e) {
  const images = [...(e.clipboardData?.items || [])].filter((i) => i.type.startsWith('image/'))
  if (!images.length) return
  e.preventDefault()
  for (const item of images) {
    const blob = item.getAsFile()
    if (!blob) continue
    const cid = `local-${Math.random().toString(36).slice(2, 10)}`
    inlineImages.value.push({ cid, file: new File([blob], cid, { type: blob.type }) })
    const img = document.createElement('img')
    img.src = URL.createObjectURL(blob)
    img.setAttribute('data-local-cid', cid)
    const selection = window.getSelection()
    if (selection?.rangeCount && editorEl.value.contains(selection.anchorNode)) {
      selection.getRangeAt(0).insertNode(img)
      selection.collapseToEnd()
    } else {
      editorEl.value.appendChild(img)
    }
    emit('input')
  }
}

function escapeHtml(text) {
  const div = document.createElement('div')
  div.textContent = text
  return div.innerHTML
}

defineExpose({
  focus: () => editorEl.value?.focus(),
  hasContent: () => editorEl.value && (editorEl.value.innerText.trim() !== '' || editorEl.value.querySelector('img')),
  getText: () => editorEl.value?.innerText.trim() || '',
  getRawHtml: () => editorEl.value?.innerHTML || '',
  setHtml: (html) => { if (editorEl.value) editorEl.value.innerHTML = html },
  setText: (text) => { if (editorEl.value) editorEl.value.innerHTML = escapeHtml(text).replace(/\n/g, '<br>') },
  getOutgoingHtml: () => {
    const clone = editorEl.value.cloneNode(true)
    clone.querySelectorAll('img[data-local-cid]').forEach((img) => {
      img.src = `cid:${img.getAttribute('data-local-cid')}`
      img.removeAttribute('data-local-cid')
    })
    return clone.innerHTML
  },
  getInlineImages: () => inlineImages.value.map(({ file }) => file),
  clear: () => {
    if (editorEl.value) editorEl.value.innerHTML = ''
    inlineImages.value = []
  },
})
</script>

<template>
  <div class="rich-editor">
    <div class="fmt-bar">
      <button type="button" class="ghost fmt" data-tip="Bold (⌘B)" @mousedown.prevent="exec('bold')"><b>B</b></button>
      <button type="button" class="ghost fmt" data-tip="Italic (⌘I)" @mousedown.prevent="exec('italic')"><i>I</i></button>
      <button type="button" class="ghost fmt" data-tip="Underline (⌘U)" @mousedown.prevent="exec('underline')"><u>U</u></button>
      <button type="button" class="ghost fmt" data-tip="Strikethrough" @mousedown.prevent="exec('strikeThrough')"><s>S</s></button>
      <span class="fmt-sep"></span>
      <button type="button" class="ghost fmt" data-tip="Bullet list" @mousedown.prevent="exec('insertUnorderedList')"><List :size="14" /></button>
      <button type="button" class="ghost fmt" data-tip="Numbered list" @mousedown.prevent="exec('insertOrderedList')"><ListOrdered :size="14" /></button>
      <button type="button" class="ghost fmt" data-tip="Quote" @mousedown.prevent="exec('formatBlock', 'blockquote')"><Quote :size="13" /></button>
      <button type="button" class="ghost fmt" data-tip="Link" @mousedown.prevent="addLink"><Link2 :size="14" /></button>
      <span class="fmt-sep"></span>
      <button type="button" class="ghost fmt" data-tip="Clear formatting" @mousedown.prevent="clearFormatting"><RemoveFormatting :size="14" /></button>
    </div>
    <div ref="editorEl" class="editor" contenteditable="true" role="textbox" aria-multiline="true"
         :data-placeholder="placeholder" @input="onNativeInput" @paste="onPaste"></div>
    <div class="resize-grip" aria-hidden="true" @pointerdown.prevent="startResize"><span></span></div>
  </div>
</template>
