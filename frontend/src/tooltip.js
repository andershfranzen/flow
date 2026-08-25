// Global tooltip singleton for [data-tip] elements: viewport-aware (flips
// below near the top edge, clamps horizontally), keyboard-focus friendly.
export function installTooltips() {
  const tip = document.createElement('div')
  tip.className = 'flow-tip'
  tip.setAttribute('role', 'tooltip')
  document.body.appendChild(tip)

  let anchor = null
  let timer = null
  const MARGIN = 8

  function show(el) {
    const text = el.getAttribute('data-tip')
    if (!text) return
    anchor = el
    tip.textContent = text
    tip.classList.add('measuring')
    tip.classList.add('visible')
    const r = el.getBoundingClientRect()
    const tr = tip.getBoundingClientRect()
    let top = r.top - tr.height - 7
    let below = false
    if (top < MARGIN) { top = r.bottom + 7; below = true }
    if (below && top + tr.height > innerHeight - MARGIN) top = innerHeight - tr.height - MARGIN
    const left = Math.max(MARGIN, Math.min(r.left + r.width / 2 - tr.width / 2,
                                           innerWidth - tr.width - MARGIN))
    tip.style.left = `${left}px`
    tip.style.top = `${top}px`
    tip.dataset.pos = below ? 'below' : 'above'
    tip.classList.remove('measuring')
  }

  function hide() {
    clearTimeout(timer)
    anchor = null
    tip.classList.remove('visible')
  }

  document.addEventListener('mouseover', (e) => {
    const el = e.target.closest?.('[data-tip]')
    if (!el) return
    if (el === anchor) return
    hide()
    timer = setTimeout(() => show(el), 220)
  })
  document.addEventListener('mouseout', (e) => {
    if (e.target.closest?.('[data-tip]')) hide()
  })
  document.addEventListener('focusin', (e) => {
    const el = e.target.closest?.('[data-tip]')
    if (el) show(el)
  })
  document.addEventListener('focusout', hide)
  document.addEventListener('mousedown', hide)
  window.addEventListener('scroll', hide, true)
}
