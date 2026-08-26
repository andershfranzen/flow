import test from 'node:test'
import assert from 'node:assert/strict'
import { shortTime } from '../src/format.js'

const instant = '2026-01-15T12:05:00Z'
const now = new Date('2026-01-15T13:00:00Z')

test('timestamps use the user timezone and default to 24-hour time', () => {
  const user = { locale: 'en', timezone: 'Europe/Copenhagen', ui_prefs: {} }
  assert.equal(shortTime(instant, user, now), '13:05')
  assert.equal(shortTime(instant, { ...user, timezone: 'America/New_York' }, now), '07:05')
})

test('users can select a 12-hour clock', () => {
  const user = { locale: 'en', timezone: 'Europe/Copenhagen', ui_prefs: { hour_cycle: '12' } }
  assert.match(shortTime(instant, user, now), /^01:05\sPM$/i)
})
