import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Build lands in Rails public/ so Puma serves the SPA in production.
// emptyOutDir stays false so Rails' own public files (robots.txt, icons) survive.
export default defineConfig({
  plugins: [vue()],
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
