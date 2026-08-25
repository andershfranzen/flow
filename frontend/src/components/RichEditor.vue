<script setup>
// Shared rich-text editor: toolbar, contenteditable, inline image paste (A20).
// Parents read content via the exposed methods; pasted images upload as CID
// inline attachments named by their local placeholder.
import { ref } from 'vue'

defineProps({ placeholder: { type: String, default: '' } })
const emit = defineEmits(['input'])

const editorEl = ref(null)
const inlineImages = ref([]) // { cid, file }

function exec(command, arg = null) {
  editorEl.value?.focus()
  document.execCommand(command, false, arg)
  emit('input')
}

function addLink() {
  const url = window.prompt('Link URL:', 'https://')
  if (url) exec('createLink', url)
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
      <button type="button" class="ghost fmt" data-tip="Bold" @mousedown.prevent="exec('bold')"><b>B</b></button>
      <button type="button" class="ghost fmt" data-tip="Italic" @mousedown.prevent="exec('italic')"><i>I</i></button>
      <button type="button" class="ghost fmt" data-tip="Bullet list" @mousedown.prevent="exec('insertUnorderedList')">≡</button>
      <button type="button" class="ghost fmt" data-tip="Link" @mousedown.prevent="addLink">🔗</button>
    </div>
    <div ref="editorEl" class="editor" contenteditable="true" role="textbox" aria-multiline="true"
         :data-placeholder="placeholder" @input="emit('input')" @paste="onPaste"></div>
  </div>
</template>
