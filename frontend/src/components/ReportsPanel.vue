<script setup>
import { ref, computed, onMounted } from 'vue'
import { api } from '../api'

const data = ref(null)
const days = ref(30)
const hover = ref(null) // { dayIndex, x }

// Validated palette (dataviz six checks, light surface): New / Closed.
const SERIES = [
  { key: 'new', label: 'New', color: '#5522fa' },
  { key: 'closed', label: 'Closed', color: '#1a7f37' },
]

async function load() {
  data.value = await api.get(`/api/reports?days=${days.value}`)
}
onMounted(load)

const chart = computed(() => {
  if (!data.value) return null
  const labels = []
  const rows = []
  for (let i = days.value - 1; i >= 0; i--) {
    const d = new Date(Date.now() - i * 86400000)
    const key = d.toISOString().slice(0, 10)
    labels.push(key)
    rows.push({ key, new: data.value.new_per_day[key] || 0, closed: data.value.closed_per_day[key] || 0 })
  }
  const max = Math.max(1, ...rows.flatMap((r) => [r.new, r.closed]))
  return { rows, max, labels }
})

const W = 640, H = 180, PAD = 24

function bars(row, i) {
  const { rows, max } = chart.value
  const slot = (W - PAD * 2) / rows.length
  const barW = Math.max(2, Math.min(10, (slot - 2) / 2 - 1))
  const x0 = PAD + i * slot + (slot - barW * 2 - 2) / 2
  return SERIES.map((s, si) => {
    const h = Math.round(((H - PAD) * row[s.key]) / max)
    return { x: x0 + si * (barW + 2), y: H - h, w: barW, h: Math.max(h, row[s.key] ? 2 : 0), color: s.color, value: row[s.key], series: s.label }
  })
}

function fmtDuration(seconds) {
  if (seconds == null) return '—'
  if (seconds < 3600) return `${Math.round(seconds / 60)} min`
  if (seconds < 86400) return `${(seconds / 3600).toFixed(1)} h`
  return `${(seconds / 86400).toFixed(1)} d`
}

function shortDay(key) {
  const d = new Date(key)
  return d.toLocaleDateString([], { day: 'numeric', month: 'short' })
}
</script>

<template>
  <div v-if="data">
    <div class="filter-row" style="padding:0 0 14px">
      <button v-for="d in [7, 30, 90]" :key="d" :class="{ primary: days === d }"
              style="padding:4px 14px" @click="days = d; load()">{{ d }} days</button>
    </div>

    <div class="report-tiles">
      <div class="card tile"><div class="tile-num">{{ data.totals.new }}</div><div class="tile-label">New conversations</div></div>
      <div class="card tile"><div class="tile-num">{{ data.totals.closed }}</div><div class="tile-label">Closed</div></div>
      <div class="card tile"><div class="tile-num">{{ data.totals.open_now }}</div><div class="tile-label">Open right now</div></div>
      <div class="card tile"><div class="tile-num">{{ fmtDuration(data.totals.avg_first_reply_seconds) }}</div><div class="tile-label">Avg. first reply</div></div>
    </div>

    <div class="card">
      <div style="display:flex; align-items:center; gap:14px; margin-bottom:8px">
        <h3 style="margin:0">Per day</h3>
        <span v-for="s in SERIES" :key="s.key" style="display:inline-flex; align-items:center; gap:5px; font-size:12.5px; font-weight:700; color:var(--muted)">
          <span :style="{ background: s.color, width: '10px', height: '10px', borderRadius: '3px', display: 'inline-block' }"></span>{{ s.label }}
        </span>
      </div>
      <div style="overflow-x:auto">
        <svg :viewBox="`0 0 ${W} ${H + 22}`" style="width:100%; min-width:480px" role="img" aria-label="New and closed conversations per day">
          <line :x1="PAD" :y1="H" :x2="W - PAD" :y2="H" stroke="var(--border)" stroke-width="1.5" />
          <g v-for="(row, i) in chart.rows" :key="row.key">
            <rect v-for="b in bars(row, i)" :key="b.series" :x="b.x" :y="b.y" :width="b.w" :height="b.h"
                  :fill="b.color" rx="2">
              <title>{{ shortDay(row.key) }} — {{ b.series }}: {{ b.value }}</title>
            </rect>
            <text v-if="days <= 7 || i % Math.ceil(days / 8) === 0" :x="PAD + i * ((W - PAD * 2) / chart.rows.length) + 6"
                  :y="H + 15" font-size="9.5" fill="var(--muted)" text-anchor="middle">{{ shortDay(row.key) }}</text>
          </g>
        </svg>
      </div>
    </div>

    <div class="report-tables">
      <div class="card" style="flex:1; padding:0">
        <table>
          <thead><tr><th>Agent</th><th style="text-align:right">Replies</th><th style="text-align:right">Closed</th></tr></thead>
          <tbody>
            <tr v-for="a in data.by_agent" :key="a.name">
              <td>{{ a.name }}</td>
              <td style="text-align:right">{{ a.replies }}</td>
              <td style="text-align:right">{{ a.closed }}</td>
            </tr>
            <tr v-if="!data.by_agent.length"><td colspan="3" style="color:var(--muted)">No activity in this window</td></tr>
          </tbody>
        </table>
      </div>
      <div class="card" style="flex:1; padding:0">
        <table>
          <thead><tr><th>Mailbox</th><th style="text-align:right">New</th><th style="text-align:right">Open</th></tr></thead>
          <tbody>
            <tr v-for="m in data.by_mailbox" :key="m.name">
              <td>{{ m.name }}</td>
              <td style="text-align:right">{{ m.new }}</td>
              <td style="text-align:right">{{ m.open }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
