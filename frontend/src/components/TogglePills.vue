<script setup>
// Multi-select as toggleable cards: click to grant, click to revoke.
import { Check } from 'lucide-vue-next'

const props = defineProps({
  options: { type: Array, required: true }, // [{ id, label, sub }]
  modelValue: { type: Array, required: true },
})
const emit = defineEmits(['update:modelValue'])

function toggle(id) {
  const next = new Set(props.modelValue)
  next.has(id) ? next.delete(id) : next.add(id)
  emit('update:modelValue', [...next])
}
</script>

<template>
  <div class="pill-select">
    <button v-for="o in options" :key="o.id" type="button" class="pill-option"
            :class="{ on: modelValue.includes(o.id) }" :aria-pressed="modelValue.includes(o.id)"
            @click="toggle(o.id)">
      <span class="pill-check"><Check :size="12" /></span>
      <span class="pill-texts">
        <span class="pill-label">{{ o.label }}</span>
        <span v-if="o.sub" class="pill-sub">{{ o.sub }}</span>
      </span>
    </button>
  </div>
</template>
