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
    proxy: Object.fromEntries(
      ['/api', '/mcp', '/rails', '/oauth', '/health'].map((path) => [
        path,
        // changeOrigin must stay false: Rails' CSRF origin check compares the
        // browser Origin (5173) against the Host it receives.
        { target: 'http://localhost:3111', changeOrigin: false },
      ])
    ),
  },
})
