import test from 'node:test'
import assert from 'node:assert/strict'
import { dialog, dialogState } from '../src/dialog.js'

function resolveOpen(result) {
  dialogState.open = false
  dialogState.resolve?.(result)
  dialogState.resolve = null
}

test('prompt resolves the entered value, confirm resolves booleans', async () => {
  const p = dialog.prompt('Name?', { initial: 'x' })
  assert.equal(dialogState.open, true)
  assert.equal(dialogState.input, 'x')
  resolveOpen(dialogState.input)
  assert.equal(await p, 'x')

  const c = dialog.confirm('Sure?', { danger: true })
  assert.equal(dialogState.danger, true)
  resolveOpen(false)
  assert.equal(await c, false)
})

test('a dialog opened over another cancels the first instead of hanging it', async () => {
  const first = dialog.confirm('First?')
  const second = dialog.prompt('Second?')
  assert.equal(await first, false)
  resolveOpen('done')
  assert.equal(await second, 'done')
})
