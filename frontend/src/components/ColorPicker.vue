<script setup>
// Styled HSV picker popover: saturation/value square + hue bar, no native UI.
// The hex field next to the swatch stays the keyboard-accessible path.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'

const props = defineProps({ modelValue: { type: String, default: '#5522fa' } })
const emit = defineEmits(['update:modelValue', 'close'])

const h = ref(0)
const s = ref(1)
const v = ref(1)
const rootEl = ref(null)

function hexToHsv(hex) {
  const n = parseInt(hex.slice(1), 16)
  const r = (n >> 16) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
  let hue = 0
  if (d) {
    if (max === r) hue = ((g - b) / d + 6) % 6
    else if (max === g) hue = (b - r) / d + 2
    else hue = (r - g) / d + 4
    hue *= 60
  }
  return { h: hue, s: max ? d / max : 0, v: max }
}

function hsvToHex(h, s, v) {
  const f = (n) => {
    const k = (n + h / 60) % 6
    const c = v - v * s * Math.max(0, Math.min(k, 4 - k, 1))
    return Math.round(c * 255).toString(16).padStart(2, '0')
  }
  return `#${f(5)}${f(3)}${f(1)}`
}

const current = computed(() => hsvToHex(h.value, s.value, v.value))
const hueColor = computed(() => hsvToHex(h.value, 1, 1))

function sync() {
  if (/^#[0-9a-fA-F]{6}$/.test(props.modelValue) && current.value !== props.modelValue.toLowerCase()) {
    const p = hexToHsv(props.modelValue.toLowerCase())
    h.value = p.h; s.value = p.s; v.value = p.v
  }
}

function drag(el, apply) {
  return (down) => {
    down.preventDefault()
    const rect = el().getBoundingClientRect()
    const move = (e) => {
      apply(Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width)),
            Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height)))
      emit('update:modelValue', current.value)
    }
    move(down)
    const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up) }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
  }
}

const squareEl = ref(null)
const hueEl = ref(null)
const onSquare = drag(() => squareEl.value, (x, y) => { s.value = x; v.value = 1 - y })
const onHue = drag(() => hueEl.value, (x) => { h.value = x * 360 })

function onDocDown(e) {
  // clicks on the owning swatch toggle the popover themselves
  if (!rootEl.value?.contains(e.target) && !rootEl.value?.parentElement?.contains(e.target)) emit('close')
}
function onKey(e) { if (e.key === 'Escape') emit('close') }

onMounted(() => {
  sync()
  document.addEventListener('pointerdown', onDocDown)
  document.addEventListener('keydown', onKey)
})
onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', onDocDown)
  document.removeEventListener('keydown', onKey)
})
</script>

<template>
  <div ref="rootEl" class="color-pop" role="dialog" aria-label="Color picker">
    <div ref="squareEl" class="cp-square" :style="{ background: `linear-gradient(to top, #000, transparent), linear-gradient(to right, #fff, ${hueColor})` }"
         @pointerdown="onSquare">
      <span class="cp-knob" :style="{ left: `${s * 100}%`, top: `${(1 - v) * 100}%`, background: current }" />
    </div>
    <div ref="hueEl" class="cp-hue" @pointerdown="onHue">
      <span class="cp-knob" :style="{ left: `${(h / 360) * 100}%`, top: '50%', background: hueColor }" />
    </div>
    <div class="cp-preview"><span class="cp-chip" :style="{ background: current }" /><code>{{ current }}</code></div>
  </div>
</template>
