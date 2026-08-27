import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Some tunnels (forwarded ports from cloud dev sessions) pass HTTP but drop
// websockets, killing HMR. Dev-only fallback: the client tries the HMR
// websocket first; if it can't connect it polls /__stamp and reloads the page
// whenever a source file changes. Does nothing in production builds.
const reloadFallback = () => {
  let stamp = String(Date.now())
  return {
    name: 'reload-fallback',
    apply: 'serve',
    configureServer(server) {
      server.watcher.on('change', () => { stamp = String(Date.now()) })
      server.watcher.on('add', () => { stamp = String(Date.now()) })
      server.middlewares.use('/__stamp', (_req, res) => {
        res.setHeader('Cache-Control', 'no-store')
        res.end(stamp)
      })
    },
    transformIndexHtml() {
      return [ { tag: 'script', injectTo: 'body', children: `
(() => {
  let armed = false
  const arm = () => {
    if (armed) return
    armed = true
    console.warn('[dev] HMR websocket unreachable - auto-reloading via polling instead')
    let last = null
    setInterval(async () => {
      try {
        const s = await (await fetch('/__stamp', { cache: 'no-store' })).text()
        if (last && s !== last) location.reload()
        last = s
      } catch {}
    }, 1200)
  }
  try {
    const ws = new WebSocket(location.origin.replace(/^http/, 'ws'), 'vite-hmr')
    let opened = false
    ws.addEventListener('open', () => { opened = true; ws.close() })
    ws.addEventListener('error', () => { if (!opened) arm() })
    setTimeout(() => { if (!opened) { arm(); try { ws.close() } catch {} } }, 4000)
  } catch { arm() }
})()` } ]
    },
  }
}

// Build lands in Rails public/ so Puma serves the SPA in production.
// emptyOutDir stays false so Rails' own public files (robots.txt, icons) survive.
export default defineConfig({
  plugins: [vue(), reloadFallback()],
  build: {
    outDir: '../public',
    emptyOutDir: false,
  },
  server: {
    port: 5173,
    strictPort: true,
    // Remote/tunneled dev (e.g. a forwarded port from a cloud session): listen
    // on all interfaces, accept any Host the tunnel presents, and point the
    // HMR websocket client at the forwarded port.
    host: true,
    allowedHosts: true,
    hmr: { clientPort: 5173 },
    proxy: Object.fromEntries(
      ['/api', '/mcp', '/rails', '/oauth', '/auth', '/health'].map((path) => [
        path,
        // changeOrigin must stay false: Rails' CSRF origin check compares the
        // browser Origin (5173) against the Host it receives.
        { target: 'http://localhost:3111', changeOrigin: false },
      ])
    ),
  },
})
