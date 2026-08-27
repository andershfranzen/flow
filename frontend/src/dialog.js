// Global replacement for window.alert/confirm/prompt — styled, promise-based.
// Rendered by GlobalDialog.vue (mounted once in App.vue).
import { reactive } from 'vue'

export const dialogState = reactive({
  open: false, kind: 'alert', message: '', input: '', placeholder: '', danger: false, resolve: null,
})

function show(opts) {
  // A dialog opened over another cancels the first so its caller never hangs.
  dialogState.resolve?.(dialogState.kind === 'confirm' ? false : null)
  return new Promise((resolve) => {
    Object.assign(dialogState, { open: true, input: '', placeholder: '', danger: false, ...opts, resolve })
  })
}

export const dialog = {
  alert: (message) => show({ kind: 'alert', message }),
  // resolves true/false
  confirm: (message, { danger = false } = {}) => show({ kind: 'confirm', message, danger }),
  // resolves the entered string, or null on cancel
  prompt: (message, { initial = '', placeholder = '' } = {}) => show({ kind: 'prompt', message, input: initial, placeholder }),
}
