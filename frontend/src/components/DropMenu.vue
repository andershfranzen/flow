<script setup>
// Pill trigger + panel teleported to <body>, so ancestor overflow/stacking
// can't clip or inline-flow the menu. Flips to a drop-up near the bottom.
import { ref, nextTick, onBeforeUnmount } from 'vue'

defineProps({ ariaLabel: { type: String, default: 'More actions' } })

const open = ref(false)
const triggerEl = ref(null)
const panelEl = ref(null)
const style = ref({})

async function toggle() {
  if (open.value) return close()
  open.value = true
  await nextTick()
  place()
  document.addEventListener('pointerdown', onDocDown)
  window.addEventListener('resize', close)
}

function place() {
  const rect = triggerEl.value.getBoundingClientRect()
  const panel = panelEl.value
  if (!panel) return
  const spaceBelow = window.innerHeight - rect.bottom
  const top = panel.offsetHeight + 12 > spaceBelow && rect.top > spaceBelow
    ? rect.top - panel.offsetHeight - 6
    : rect.bottom + 6
  const left = Math.min(Math.max(8, rect.right - panel.offsetWidth), window.innerWidth - panel.offsetWidth - 8)
  style.value = { top: `${top}px`, left: `${left}px` }
}

function close() {
  open.value = false
  document.removeEventListener('pointerdown', onDocDown)
  window.removeEventListener('resize', close)
}

function onDocDown(e) {
  if (!panelEl.value?.contains(e.target) && !triggerEl.value?.contains(e.target)) close()
}

onBeforeUnmount(close)
defineExpose({ close })
</script>

<template>
  <button ref="triggerEl" type="button" class="pill drop-trigger" :aria-expanded="open"
          aria-haspopup="menu" :aria-label="ariaLabel" @click="toggle">
    <slot name="trigger" />
  </button>
  <Teleport to="body">
    <div v-if="open" ref="panelEl" class="card menu-card drop-panel" :style="style" @keydown.esc="close">
      <slot :close="close" />
    </div>
  </Teleport>
</template>
