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
    proxy: {
      '/api': 'http://localhost:3000',
      '/mcp': 'http://localhost:3000',
      '/rails': 'http://localhost:3000',
    },
  },
})
