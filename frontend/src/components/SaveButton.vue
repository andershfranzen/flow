<script setup>
// Primary save button that morphs into a green "Saved ✓" while `saved` is true.
import { Check } from 'lucide-vue-next'
defineProps({ saved: Boolean, label: { type: String, default: 'Save' } })
</script>

<template>
  <button class="primary save-button" :class="{ 'is-saved': saved }">
    <Transition name="save-swap" mode="out-in">
      <span v-if="saved" class="save-face"><Check :size="15" /> Saved</span>
      <span v-else class="save-face">{{ label }}</span>
    </Transition>
  </button>
</template>
